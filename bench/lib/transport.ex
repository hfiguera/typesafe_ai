defmodule TypeSafe.Bench.Transport do
  @moduledoc false
  alias TypeSafe.{Request, Response}

  def start(%{profile: "defaults", client: "typesafe"} = s) do
    opts = config(s) |> Keyword.drop([:max_concurrency, :max_queue, :protocols])
    {:ok, pid} = TypeSafe.Client.start_link(opts)
    {fn input -> TypeSafe.system_one(pid, input) end, fn -> Supervisor.stop(pid) end}
  end

  def start(%{profile: "defaults", client: "jev"} = s) do
    before = req_pools()
    previous = Application.fetch_env(:jev, :req_options)

    Application.put_env(:jev, :req_options,
      connect_options: [transport_opts: transport_opts(s)],
      redirect: false
    )

    {http_call("jev", s),
     fn ->
       restore_jev(previous)
       stop_new_req_pools(before)
     end}
  end

  def start(%{profile: "defaults", client: "typesafe_api"} = s),
    do: start_typesafe_api(s, transport_opts: transport_opts(s))

  def start(%{profile: "defaults", client: "typesafe_sdk", target: :offline} = s) do
    # Only in a disposable offline benchmark VM. This changes its CA cache, not
    # the OS trust store. The unmodified SDK uses :httpc's verified HTTPS/1 path.
    :ok = :public_key.cacerts_load(ca())

    client =
      TypeSafeSDK.new_client(
        api_key: api_key(s),
        base_url: url(s),
        model: model(s),
        retry: false,
        timeout_ms: 1000
      )

    {fn opts ->
       TypeSafeSDK.evaluate(client, opts[:state], opts[:questions],
         timeout_ms: opts[:timeout] || 30_000
       )
     end,
     fn ->
       :public_key.cacerts_clear()
       :public_key.cacerts_load()
     end}
  end

  def start(%{client: "typesafe_sdk"}) do
    raise ArgumentError,
          "typesafe_sdk requires the offline defaults profile in a fresh VM; see COMMUNITY.md"
  end

  def start(%{client: client} = s) when client in ["finch", "req", "req_llm", "jev"] do
    pool = [
      protocols: [s.protocol],
      count: if(s.protocol == :http2, do: s.connections, else: 1),
      size: if(s.protocol == :http1, do: s.connections, else: 1),
      conn_opts: [transport_opts: transport_opts(s)]
    ]

    {:ok, pid} = Finch.start_link(name: TypeSafe.Bench.Finch, pools: %{default: pool})

    restore = configure_jev(client)

    {http_call(client, s),
     fn ->
       restore.()
       Supervisor.stop(pid)
     end}
  end

  def start(%{client: "typesafe_api", connections: 1, protocol: :http2} = s) do
    # Its public named-pool option accepts only an atom, which Req 0.7.4 warns
    # about on every request. Use its documented dynamic connection settings
    # instead: Req defaults to one HTTP/2 pool/connection. No warning suppression
    # or SDK implementation patch is part of the timed path.
    start_typesafe_api(s, protocols: [:http2], transport_opts: transport_opts(s))
  end

  def start(%{client: "typesafe_api"}) do
    raise ArgumentError, "typesafe_api adapter supports one HTTP/2 connection; see COMMUNITY.md"
  end

  def start(%{client: "manual"} = s) do
    workers =
      for _ <- 1..s.connections do
        {:ok, pid} = TypeSafe.Client.start_link(config(s))
        pid
      end

    workers = List.to_tuple(workers)
    counter = :atomics.new(1, signed: false)

    call = fn opts ->
      index = rem(:atomics.add_get(counter, 1, 1) - 1, tuple_size(workers))
      TypeSafe.system_one(elem(workers, index), opts)
    end

    {call, fn -> for pid <- Tuple.to_list(workers), do: GenServer.stop(pid) end}
  end

  def start(%{client: "typesafe"} = s) do
    {:ok, pid} = TypeSafe.Client.start_link(Keyword.put(config(s), :pool_size, s.connections))
    {fn opts -> TypeSafe.system_one(pid, opts) end, fn -> Supervisor.stop(pid) end}
  end

  defp http_call("finch", s) do
    fn opts ->
      with {:ok, request} <- Request.prepare(opts),
           body = request |> Request.body(model(s)) |> IO.iodata_to_binary(),
           req = Finch.build(:post, url(s) <> "/v1/systemone", headers(s), body),
           {:ok, %{status: 200, body: response}} <-
             Finch.request(req, TypeSafe.Bench.Finch, timeouts(request.timeout)) do
        Response.decode(response, request.schema)
      else
        {:ok, %Finch.Response{status: status}} -> http_error(status)
        {:error, _reason} = error -> error
      end
    end
  end

  defp http_call("req", s) do
    # Reuse the request template, as recommended by Req. Encoding and typed
    # decoding match the Finch adapter instead of decoding JSON twice.
    template =
      Req.new(
        method: :post,
        url: url(s) <> "/v1/systemone",
        headers: headers(s),
        finch: TypeSafe.Bench.Finch,
        retry: false,
        redirect: false,
        decode_body: false
      )

    fn opts ->
      with {:ok, request} <- Request.prepare(opts),
           body = request |> Request.body(model(s)) |> IO.iodata_to_binary(),
           {:ok, %{status: 200, body: response}} <-
             Req.request(template,
               body: body,
               receive_timeout: request.timeout || 30_000,
               finch: [name: TypeSafe.Bench.Finch] ++ timeouts(request.timeout)
             ) do
        Response.decode(response, request.schema)
      else
        {:ok, %Req.Response{status: status}} -> http_error(status)
        {:error, _reason} = error -> error
      end
    end
  end

  defp http_call("req_llm", s) do
    fn opts ->
      timeout = opts[:timeout] || 30_000

      ReqLLM.evaluate("typesafe:" <> model(s), opts[:state], opts[:questions],
        api_key: api_key(s),
        base_url: url(s),
        receive_timeout: timeout,
        total_timeout: timeout,
        max_retries: 0,
        req_http_options: [
          finch: [name: TypeSafe.Bench.Finch] ++ timeouts(timeout),
          redirect: false
        ]
      )
    end
  end

  defp http_call("jev", s) do
    fn opts ->
      Jev.HTTP.post(opts[:state], opts[:questions],
        api_key: api_key(s),
        base_url: url(s),
        model: model(s),
        max_retries: 0,
        receive_timeout: opts[:timeout] || 30_000
      )
    end
  end

  defp start_typesafe_api(s, connect_options) do
    before = req_pools()

    client =
      TypeSafeAPI.new(
        api_key: api_key(s),
        base_url: url(s),
        model: model(s),
        retry: [max_retries: 0],
        req_options: [redirect: false, connect_options: connect_options]
      )

    call = fn opts ->
      TypeSafeAPI.evaluate(client, opts[:state], opts[:questions],
        timeout: opts[:timeout] || 30_000
      )
    end

    {call, fn -> stop_new_req_pools(before) end}
  end

  defp req_pools,
    do: DynamicSupervisor.which_children(Req.FinchSupervisor) |> Enum.map(&elem(&1, 1))

  defp stop_new_req_pools(before) do
    for pid <- req_pools() -- before,
        do: DynamicSupervisor.terminate_child(Req.FinchSupervisor, pid)
  end

  defp restore_jev({:ok, value}), do: Application.put_env(:jev, :req_options, value)
  defp restore_jev(:error), do: Application.delete_env(:jev, :req_options)

  # Jev 0.1.0 exposes transport injection through application config only.
  # Scenarios run sequentially and restore the caller's configuration on teardown.
  defp configure_jev("jev") do
    previous = Application.fetch_env(:jev, :req_options)
    Application.put_env(:jev, :req_options, finch: [name: TypeSafe.Bench.Finch], redirect: false)

    fn -> restore_jev(previous) end
  end

  defp configure_jev(_), do: fn -> :ok end

  # Question construction is outside the timed API call for every client.
  def input("req_llm", opts) do
    {:ok, questions} = TypeSafe.Question.to_wire(opts[:questions])
    Keyword.put(opts, :questions, questions)
  end

  def input(client, opts) when client in ["jev", "typesafe_api"] do
    questions =
      Map.new(opts[:questions], fn {id, q} ->
        case client do
          "jev" ->
            # Only trusted, finite benchmark question IDs/labels become atoms;
            # conversion happens before timing, never from server responses.
            criteria =
              if q.type == :choice,
                do: Map.new(q.criteria, fn {k, v} -> {String.to_atom(k), v} end),
                else: q.criteria

            module = %{noul: Jev.Noul, choice: Jev.Choice, score: Jev.Score}[q.type]

            {String.to_atom(id),
             struct!(module, instructions: q.instructions, criteria: criteria)}

          "typesafe_api" ->
            question =
              case q.type do
                :noul -> TypeSafeAPI.noul(q.instructions, q.criteria)
                :choice -> TypeSafeAPI.choice(q.instructions, Enum.sort(q.criteria))
                :score -> TypeSafeAPI.score(q.instructions, q.criteria)
              end

            {id, question}
        end
      end)

    questions = if client == "typesafe_api", do: Enum.sort(questions), else: questions
    Keyword.put(opts, :questions, questions)
  end

  def input("typesafe_sdk", opts) do
    questions =
      Map.new(opts[:questions], fn {id, q} ->
        question =
          case q.type do
            :noul -> TypeSafeSDK.noul(q.instructions, criteria: q.criteria)
            :choice -> TypeSafeSDK.choice(q.instructions, Enum.sort(q.criteria))
            :score -> TypeSafeSDK.score(q.instructions, q.criteria)
          end

        {id, question}
      end)

    Keyword.put(opts, :questions, questions)
  end

  def input(_client, opts), do: opts

  def ready(call, opts, remaining \\ 30_000) do
    result = call.(opts)

    if remaining > 0 and starting?(result) do
      Process.sleep(10)
      ready(call, opts, remaining - 10)
    else
      result
    end
  end

  defp starting?({:error, %{reason: :pool_not_available}}), do: true

  defp starting?(
         {:error,
          %TypeSafeAPI.Error{type: :connection, message: "http2 error: :pool_not_available"}}
       ),
       do: true

  defp starting?({:error, %{cause: cause}}), do: starting?({:error, cause})
  defp starting?(_result), do: false

  defp timeouts(timeout) do
    timeout = timeout || 30_000
    [pool_timeout: timeout, receive_timeout: timeout, request_timeout: timeout]
  end

  defp headers(s) do
    [
      {"authorization", "Bearer " <> api_key(s)},
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ]
  end

  defp http_error(status),
    do: {:error, TypeSafe.Error.new(:http, "Benchmark HTTP error", status)}

  defp config(s),
    do: [
      api_key: api_key(s),
      base_url: url(s),
      protocols: [s.protocol],
      model: model(s),
      max_concurrency: s.max_concurrency,
      max_queue: s.max_queue,
      transport_opts: transport_opts(s)
    ]

  # Live access is explicit and pinned to the service origin. Offline callers
  # never read a credential, even when TYPESAFE_API_KEY exists in their environment.
  defp api_key(%{target: :live}), do: System.fetch_env!("TYPESAFE_API_KEY")
  defp api_key(_s), do: "benchmark-only"
  defp model(%{target: :live} = s), do: Map.fetch!(s, :model)
  defp model(%{recording: recording}) when not is_nil(recording), do: recording.request["model"]
  defp model(_s), do: "jev-benchmark"
  defp transport_opts(%{target: :live}), do: []
  defp transport_opts(_s), do: [cacertfile: ca()]
  defp url(%{target: :live}), do: "https://api.typesafe.ai"

  defp url(%{recording: recording} = s) when not is_nil(recording),
    do:
      "https://localhost:#{System.get_env("BENCH_PORT", "8443")}/#{s.delay}/recorded/#{recording.id}"

  defp url(s), do: "https://localhost:#{System.get_env("BENCH_PORT", "8443")}/#{s.delay}"
  defp ca, do: Path.expand("../../test/fixtures/ca.pem", __DIR__) |> String.to_charlist()
end
