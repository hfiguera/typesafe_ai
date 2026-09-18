alias TypeSafe.Bench.{Recordings, Transport}
recordings = Recordings.load()

rows =
  for protocol <- [:http1, :http2],
      client <- ~w(typesafe finch req req_llm),
      {id, recording} <- Enum.sort(recordings) do
    scenario = %{
      protocol: protocol,
      client: client,
      recording: recording,
      connections: 2,
      delay: 0,
      max_concurrency: 10,
      max_queue: 100
    }

    {call, stop} = Transport.start(scenario)

    try do
      input =
        Transport.input(client, recording.input ++ [timeout: 5000, retry: [max_attempts: 1]])

      {:ok, response} = Transport.ready(call, input)

      if client == "req_llm" do
        true = response.provider_meta.raw_response == JSON.decode!(recording.response_body)
      else
        true = response == recording.response
      end

      %{
        client: client,
        protocol: protocol,
        recording_id: id,
        outcome: "ok",
        response_bytes: recording.response_bytes
      }
    after
      stop.()
    end
  end

path = System.get_env("BENCH_SMOKE_OUTPUT", "results/replay-smoke.json")
File.mkdir_p!(Path.dirname(path))
File.write!(path, JSON.encode!(%{kind: "offline_recorded_response_smoke", results: rows}))

IO.puts(
  "All #{length(rows)} recorded-response checks passed across four clients and both HTTP versions"
)
