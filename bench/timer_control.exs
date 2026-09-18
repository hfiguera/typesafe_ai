# Exercise the same arrival driver with no client, JSON, TLS or network.
alias TypeSafe.Bench.{Load, Runner}

defmodule TimerControlWork do
  def until(deadline) do
    if System.monotonic_time(:microsecond) < deadline, do: until(deadline), else: :ok
  end
end

{opts, [], []} =
  OptionParser.parse(System.argv(),
    strict: [output: :string, requests: :integer, rate: :integer, work_us: :integer]
  )

rate = Keyword.get(opts, :rate, 1000)
requests = Keyword.get(opts, :requests, 5000)
work_us = Keyword.get(opts, :work_us, 0)
true = work_us >= 0

call = fn _ ->
  if work_us > 0, do: TimerControlWork.until(System.monotonic_time(:microsecond) + work_us)
  Process.sleep(5)
  {:ok, nil}
end

before = Runner.snapshot()
origin = System.monotonic_time(:microsecond)

result =
  Load.drive(call, %{regular: [], small: [], large_every: 0},
    rate: rate,
    requests: requests,
    max_in_flight: 512,
    origin: origin,
    snapshot: true
  )

report = %{
  kind: "timer_only_control",
  note: "Same arrival driver, Process.sleep(5), no client or network; not HTTP performance.",
  diagnostic_cpu_work_us: work_us,
  environment: Runner.environment(),
  offered_requests: requests,
  offered_rps: rate,
  outcomes: Enum.frequencies_by(result.samples, &elem(&1, 1)),
  driver_dropped: result.dropped,
  driver_launch_lag_ms: Runner.percentiles(Enum.map(result.samples, &elem(&1, 2))),
  success_latency_from_scheduled_arrival_ms:
    Runner.percentiles(Enum.map(result.samples, fn {us, _, lag, _, _} -> us + lag end)),
  vm_cpu_ms: result.finished_snapshot.cpu - before.cpu,
  elapsed_ms: (result.finished_at - origin) / 1000,
  timeline: result.timeline
}

File.write!(Keyword.fetch!(opts, :output), JSON.encode!(report))
