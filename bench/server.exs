port = System.get_env("BENCH_PORT", "8443") |> String.to_integer()
address = System.get_env("BENCH_BIND_IP", "127.0.0.1")
{:ok, ip} = :inet.parse_address(String.to_charlist(address))

opts =
  case System.get_env("BENCH_RECORDINGS") do
    nil -> [ip: ip]
    path -> [ip: ip, recordings: TypeSafe.Bench.Recordings.load(path)]
  end

{:ok, _server} = TypeSafe.Bench.Server.start_link(port, opts)
IO.puts("Benchmark fixture listening on #{address}:#{port}; TLS name localhost; no API calls")
Process.sleep(:infinity)
