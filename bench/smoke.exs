# Harness correctness only: server and client share this VM, so these are not
# performance results. Ephemeral port avoids conflicting with other fixtures.
{:ok, server} = TypeSafe.Bench.Server.start_link(0)
{:ok, {_ip, port}} = ThousandIsland.listener_info(server)
System.put_env("BENCH_PORT", Integer.to_string(port))

output =
  Path.join(System.tmp_dir!(), "typesafe-bench-smoke-#{System.unique_integer([:positive])}.json")

try do
  TypeSafe.Bench.Runner.run([
    "--clients",
    "typesafe,finch,req,req_llm",
    "--protocols",
    "http1,http2",
    "--connections",
    "1,2",
    "--concurrency",
    "4",
    "--delays",
    "0",
    "--payloads",
    "256:1",
    "--requests",
    "32",
    "--repetitions",
    "1",
    "--output",
    output
  ])

  %{"results" => results} = output |> File.read!() |> JSON.decode!()
  true = length(results) == 16
  true = Enum.all?(results, &(&1["outcomes"] == %{"ok" => 32}))

  TypeSafe.Bench.Runner.run([
    "--clients",
    "typesafe,finch,req,req_llm",
    "--protocols",
    "http2",
    "--connections",
    "1",
    "--concurrency",
    "4",
    "--delays",
    "0",
    "--payloads",
    "65536:32",
    "--large-every",
    "4",
    "--requests",
    "16",
    "--warmup",
    "4",
    "--repetitions",
    "1",
    "--output",
    output
  ])

  %{"results" => mixed} = output |> File.read!() |> JSON.decode!()
  true = length(mixed) == 4

  for result <- mixed do
    %{"small" => %{"outcomes" => %{"ok" => 12}}, "large" => %{"outcomes" => %{"ok" => 4}}} =
      result["workloads"]
  end

  for client <- ["typesafe", "finch", "req", "req_llm"] do
    TypeSafe.Bench.Load.run([
      "--large-every",
      "4",
      "--bytes",
      "65536",
      "--client",
      client,
      "--rate",
      "100",
      "--requests",
      "20",
      "--connections",
      "2",
      "--output",
      output
    ])

    %{
      "outcomes" => %{"ok" => 20},
      "driver_dropped" => 0,
      "workloads" => %{
        "small" => %{"outcomes" => %{"ok" => 15}},
        "large" => %{"outcomes" => %{"ok" => 5}}
      }
    } =
      output |> File.read!() |> JSON.decode!()
  end

  TypeSafe.Bench.Curves.run([
    "--rates",
    "100",
    "--connections",
    "1",
    "--workloads",
    "small",
    "--seconds",
    "1",
    "--repetitions",
    "1",
    "--min-samples",
    "20",
    "--output",
    output
  ])

  %{"complete" => true, "results" => curves, "capacity" => capacity} =
    output |> File.read!() |> JSON.decode!()

  true = length(curves) == 4 and length(capacity) == 4
  true = Enum.all?(curves, &(&1["outcomes"] == %{"ok" => 100} and &1["driver_dropped"] == 0))

  IO.puts("Benchmark harness smoke passed")
after
  Supervisor.stop(server)
  File.rm(output)
end
