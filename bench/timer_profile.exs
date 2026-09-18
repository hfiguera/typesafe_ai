# Use only with the archived instrumented library snapshot, not a timing claim.
alias TypeSafe.Bench.{Load, Runner}
:ets.new(:typesafe_timer_profile, [:named_table, :public, :set, write_concurrency: true])
report = Load.run(System.argv())
times = for {_, us} <- :ets.tab2list(:typesafe_timer_profile), do: us
{opts, _, _} = OptionParser.parse(System.argv(), strict: [output: :string])

File.write!(
  opts[:output] <> ".profile.json",
  JSON.encode!(%{
    note: "Instrumented synchronous timer cancellation; instrumentation perturbs timing.",
    cancellations: length(times),
    cancel_ms: Runner.percentiles(times),
    max_cancel_ms: Enum.max(times) / 1000,
    cancellations_over_1ms: Enum.count(times, &(&1 > 1000)),
    source_sha256: report.source_sha256
  })
)
