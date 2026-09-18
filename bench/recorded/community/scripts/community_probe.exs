# Offline behavior observations, separate from timing comparisons.
alias TypeSafe.Bench.{Runner, Server, Transport}

defmodule CommunityProbe do
  def run(client, name, fixture_opts, delay, timeout) do
    scheme = if client == "typesafe_sdk", do: :http, else: :https
    {:ok, server} = Server.start_link(0, [observer: self(), scheme: scheme] ++ fixture_opts)
    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    previous = System.get_env("BENCH_PORT")
    System.put_env("BENCH_PORT", to_string(port))
    questions = %{"q1" => TypeSafe.noul("True?")}

    input =
      Transport.input(client,
        state: "synthetic",
        questions: questions,
        timeout: timeout,
        retry: [max_attempts: 1]
      )

    {call, stop} =
      if client == "typesafe_sdk" do
        sdk =
          TypeSafeSDK.new_client(
            api_key: "benchmark-only",
            model: "jev-benchmark",
            base_url: "http://localhost:#{port}/#{delay}",
            retry: false,
            timeout_ms: timeout
          )

        {fn _ -> TypeSafeSDK.evaluate(sdk, "synthetic", %{"q1" => TypeSafeSDK.noul("True?")}) end,
         fn -> :ok end}
      else
        Transport.start(%{
          client: client,
          connections: 1,
          protocol: :http2,
          delay: delay,
          max_concurrency: 10,
          max_queue: 100
        })
      end

    try do
      started = System.monotonic_time(:microsecond)

      result =
        try do
          Transport.ready(call, input)
        rescue
          e -> {:raised, e.__struct__}
        catch
          kind, _ -> {:caught, kind}
        end

      elapsed = (System.monotonic_time(:microsecond) - started) / 1000
      Process.sleep(250)
      observed = drain([])

      %{
        client: client,
        case: name,
        result: classify(result),
        elapsed_ms: elapsed,
        fixture_requests: length(observed),
        protocols: Enum.uniq(Enum.map(observed, &to_string(&1.protocol))),
        scheme: scheme,
        retries: "disabled",
        includes_connection_startup: true
      }
    after
      stop.()
      Supervisor.stop(server)

      if previous,
        do: System.put_env("BENCH_PORT", previous),
        else: System.delete_env("BENCH_PORT")
    end
  end

  defp classify({:ok, _}), do: %{outcome: "ok"}

  defp classify({:error, e}),
    do: %{
      outcome: "error",
      type:
        to_string(Map.get(e, :kind) || Map.get(e, :type) || Map.get(e, :reason) || e.__struct__),
      status: Map.get(e, :status)
    }

  defp classify({kind, detail}), do: %{outcome: to_string(kind), type: to_string(detail)}

  defp drain(acc) do
    receive do
      {:fixture_request, request} -> drain([request | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end

{opts, [], []} = OptionParser.parse(System.argv(), strict: [output: :string])
base = %{"model" => "jev-benchmark", "usage" => %{"input_tokens" => 12, "output_tokens" => 2}}

cases = [
  {"success", [], 0, 1000},
  {"http_429", [status: 429], 0, 1000},
  {"http_529", [status: 529], 0, 1000},
  {"missing_answer", [body: JSON.encode!(Map.put(base, "answers", %{}))], 0, 1000},
  {"invalid_probability",
   [body: JSON.encode!(Map.put(base, "answers", %{"q1" => %{"type" => "noul", "noul" => 2.0}}))],
   0, 1000},
  {"invalid_json", [body: "{"], 0, 1000},
  {"slow_response", [], 200, 100}
]

rows =
  for client <- ~w(typesafe jev typesafe_api typesafe_sdk),
      {name, fixture, delay, timeout} <- cases,
      do: CommunityProbe.run(client, name, fixture, delay, timeout)

report = %{
  kind: "offline_community_behavior",
  environment: Runner.environment(),
  cases: rows,
  note:
    "SDK uses plain loopback HTTP because its default transport ignores the private CA setting. Other clients use verified HTTPS/2. These are behavior probes, not timing rankings."
}

File.write!(Keyword.fetch!(opts, :output), JSON.encode!(report))
IO.puts("Recorded #{length(rows)} offline behavior observations")
