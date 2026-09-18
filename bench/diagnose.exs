# Diagnostic only: sampling/monitoring changes scheduling. Do not rank clients
# using these runs. No request arguments, responses, or credentials are recorded.
owner = self()
{:ok, samples} = Agent.start_link(fn -> %{ticks: [], events: []} end)

sampler =
  spawn(fn ->
    origin = System.monotonic_time(:millisecond)

    receive_loop = fn loop ->
      receive do
        {:monitor, pid, kind, info} ->
          entry = %{
            at_ms: System.monotonic_time(:millisecond) - origin,
            driver: pid == owner,
            kind: kind,
            info: inspect(info),
            process: inspect(Process.info(pid, :current_function))
          }

          Agent.cast(samples, &Map.update!(&1, :events, fn es -> [entry | es] end))
          loop.(loop)

        {:stop, reply_to} ->
          # Reading from the same sender drains its preceding Agent casts.
          send(reply_to, {:diagnostics, Agent.get(samples, & &1)})
      after
        100 ->
          info =
            Process.info(owner, [
              :memory,
              :heap_size,
              :total_heap_size,
              :message_queue_len,
              :reductions
            ])

          Agent.cast(
            samples,
            &Map.update!(&1, :ticks, fn ticks ->
              [
                %{
                  at_ms: System.monotonic_time(:millisecond) - origin,
                  driver: Map.new(info || [])
                }
                | ticks
              ]
            end)
          )

          loop.(loop)
      end
    end

    receive_loop.(receive_loop)
  end)

:erlang.system_monitor(sampler, [{:long_gc, 5}, {:long_schedule, 20}])

try do
  report =
    if System.get_env("BENCH_DIAG_CURVES") == "1",
      do: TypeSafe.Bench.Curves.run(System.argv()),
      else: TypeSafe.Bench.Load.run(System.argv())

  :erlang.system_monitor(:undefined)
  send(sampler, {:stop, self()})

  diagnostics =
    receive do
      {:diagnostics, diagnostics} -> diagnostics
    after
      5_000 -> raise "diagnostic sampler did not finish"
    end

  output = System.fetch_env!("BENCH_DIAGNOSTICS")
  File.write!(output, JSON.encode!(%{report: report, diagnostics: diagnostics}))
after
  :erlang.system_monitor(:undefined)
  Process.exit(sampler, :kill)
  Agent.stop(samples)
end
