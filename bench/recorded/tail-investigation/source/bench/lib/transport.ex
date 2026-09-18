defmodule TypeSafe.Bench.Transport do
  @moduledoc false
  alias TypeSafe.{Request, Response}

  def start(%{client: client} = s) when client in ["finch", "req", "req_llm"] do
    pool = [
      protocols: [s.protocol],
      count: if(s.protocol == :http2, do: s.connections, else: 1),
      size: if(s.protocol == :http1, do: s.connections, else: 1),
      conn_opts: [transport_opts: transport_opts(s)]
    ]

    {:ok, pid} = Finch.start_link(name: TypeSafe.Bench.Finch, pools: %{default: pool})

    {http_call(client, s), fn -> Supervisor.stop(pid) end}
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

  # Question construction is outside the timed API call for every client.
  def input("req_llm", opts) do
    {:ok, questions} = TypeSafe.Question.to_wire(opts[:questions])
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
