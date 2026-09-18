defmodule TypeSafe.Bench.Curves do
  @moduledoc false
  alias TypeSafe.Bench.{Load, Runner}

  def run(args) do
    {opts, [], []} =
      OptionParser.parse(args,
        strict: [
          rates: :string,
          connections: :string,
          clients: :string,
          workloads: :string,
          seconds: :integer,
          repetitions: :integer,
          seed: :integer,
          output: :string,
          budget_ms: :integer,
          lag_budget_ms: :integer,
          delay: :integer,
          max_in_flight: :integer,
          max_concurrency: :integer,
          max_queue: :integer,
          timeout: :integer,
          min_samples: :integer,
          live: :boolean,
          sample_storage: :string
        ]
      )

    if opts[:live], do: live(opts), else: offline(opts)
  end

  defp offline(opts) do
    config = %{
      clients: strings(opts, :clients, "typesafe,finch,req,req_llm"),
      rates: numbers(opts, :rates, "500,2000,8000,16000"),
      connections: numbers(opts, :connections, "1,4"),
      workloads: strings(opts, :workloads, "small,batch,mixed"),
      seconds: Keyword.get(opts, :seconds, 2),
      repetitions: Keyword.get(opts, :repetitions, 3),
      seed: Keyword.get(opts, :seed, 20_260_917),
      budget_ms: Keyword.get(opts, :budget_ms, 20),
      lag_budget_ms: Keyword.get(opts, :lag_budget_ms, 5),
      min_samples: Keyword.get(opts, :min_samples, 1000)
    }

    true = config.seconds > 0 and config.repetitions > 0 and config.min_samples > 0
    true = config.budget_ms > 0 and config.lag_budget_ms > 0
    true = Enum.all?(config.rates ++ config.connections, &(&1 > 0))
    true = Enum.all?(config.clients, &(&1 in ~w(typesafe finch req req_llm)))
    true = Enum.all?(config.workloads, &(&1 in ~w(small batch mixed)))
    :rand.seed(:exsss, {config.seed, config.seed + 1, config.seed + 2})
    # Complete randomized blocks keep any adapter from always being first.
    scenarios =
      Enum.flat_map(1..config.repetitions, fn repetition ->
        for rate <- config.rates,
            connections <- config.connections,
            workload <- config.workloads,
            client <- config.clients do
          %{
            rate: rate,
            connections: connections,
            workload: workload,
            client: client,
            repetition: repetition
          }
        end
        |> Enum.shuffle()
      end)

    common =
      Keyword.take(opts, [
        :delay,
        :max_in_flight,
        :max_concurrency,
        :max_queue,
        :timeout,
        :sample_storage
      ])

    output = Keyword.get(opts, :output, "results/curves.json")

    base = %{
      kind: "offline_latency_curves",
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      environment: Runner.environment(),
      config: config,
      planned_scenarios: length(scenarios)
    }

    results =
      execute(scenarios, base, output, fn s ->
        count = max(config.min_samples, s.rate * config.seconds)

        measurement =
          Load.measure(
            Keyword.merge([max_concurrency: 128, max_queue: 1024], common) ++
              [
                client: s.client,
                rate: s.rate,
                connections: s.connections,
                requests: count,
                budget_ms: config.budget_ms
              ] ++ workload(s.workload)
          )

        measurement
        |> Map.merge(Map.take(s, [:repetition, :workload]))
        |> Map.put(:budget_check, qualify(measurement, config))
      end)

    write(
      output,
      Map.merge(base, %{results: results, complete: true, capacity: capacities(results)})
    )

    IO.puts("Saved #{length(results)} scenarios to #{output}")
  end

  defp live(opts) do
    # Explicit, fixed budget; no arbitrary URL, load ramp, or user data.
    true =
      is_binary(System.get_env("TYPESAFE_API_KEY")) and
        byte_size(System.get_env("TYPESAFE_API_KEY")) > 0

    forbidden = Keyword.keys(opts) -- [:live, :output, :seed]

    if forbidden != [],
      do:
        raise(
          ArgumentError,
          "live mode only accepts --output and --seed; its request budget is fixed"
        )

    seed = Keyword.get(opts, :seed, 20_260_917)
    :rand.seed(:exsss, {seed, seed + 1, seed + 2})

    scenarios =
      Enum.flat_map(1..2, fn repetition ->
        for client <- ~w(typesafe finch req req_llm), rate <- [1, 4] do
          %{client: client, rate: rate, repetition: repetition}
        end
        |> Enum.shuffle()
      end)

    base = %{
      kind: "live_jev_sanity",
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      environment:
        Map.put(
          Runner.environment(),
          :fixture,
          "live https://api.typesafe.ai; verified system TLS"
        ),
      planned_scenarios: 16,
      max_service_requests_including_warmup: 144,
      seed: seed,
      note:
        "Eight measured calls per scenario; insufficient for tail latency or capacity claims. No retries. Stops after a failing scenario."
    }

    output = Keyword.get(opts, :output, "results/live.json")

    results =
      execute(scenarios, base, output, fn s ->
        state =
          "A customer asks for a copy of their invoice for last month. They do not report a technical problem."

        Load.measure(
          client: s.client,
          rate: s.rate,
          requests: 8,
          warmup: 1,
          target: :live,
          model: "jev-latest",
          connections: 1,
          max_in_flight: 8,
          max_concurrency: 8,
          max_queue: 0,
          timeout: 5000,
          budget_ms: 1000,
          state: state,
          question: "Does the customer ask about an invoice?",
          bytes: byte_size(state)
        )
        |> Map.put(:repetition, s.repetition)
      end)

    write(output, Map.merge(base, %{results: results, complete: true}))
    IO.puts("Saved bounded live comparison to #{output}")
  end

  defp execute(scenarios, base, output, fun) do
    write(output, Map.merge(base, %{results: [], complete: false}))

    Enum.reduce(scenarios, [], fn s, acc ->
      row = fun.(s)
      results = acc ++ [row]
      write(output, Map.merge(base, %{results: results, complete: false}))

      IO.puts(
        "#{length(results)}/#{length(scenarios)} #{s.client} rate=#{s.rate} " <>
          "ok=#{row.outcomes[:ok] || 0} drops=#{row.driver_dropped} " <>
          "arrival p99=#{inspect(row.success_latency_from_scheduled_arrival_ms.p99)}ms"
      )

      if base.kind == "live_jev_sanity" and (row.outcomes != %{ok: 8} or row.driver_dropped != 0),
        do: raise("live comparison stopped after errors; partial sanitized results saved")

      results
    end)
  end

  def qualify(row, config) do
    p99 = row.success_latency_from_scheduled_arrival_ms.p99
    lag = row.driver_launch_lag_ms.p99

    reasons =
      [
        {Map.get(row.outcomes, :ok, 0) < config.min_samples, "insufficient_success_samples"},
        {row.outcomes != %{ok: row.offered_requests}, "request_errors"},
        {row.driver_dropped != 0, "driver_drops"},
        {is_nil(lag) or lag > config.lag_budget_ms, "driver_lag"},
        {is_nil(p99) or p99 > config.budget_ms, "p99_budget"},
        {row.within_budget_fraction_of_offered < 0.99,
         "fewer_than_99_percent_of_offered_within_budget"}
      ]
      |> Enum.filter(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    %{passes: reasons == [], reasons: reasons}
  end

  def capacities(rows) do
    rows
    |> Enum.group_by(&{&1.client, &1.connections, &1.workload})
    |> Enum.map(fn {{client, connections, workload}, group} ->
      # An isolated higher pass after a lower failure is not capacity evidence.
      rates = group |> Enum.group_by(& &1.offered_rps) |> Enum.sort_by(&elem(&1, 0))

      passing =
        Enum.take_while(rates, fn {_rate, reps} -> Enum.all?(reps, & &1.budget_check.passes) end)

      %{
        client: client,
        connections: connections,
        workload: workload,
        highest_tested_passing_offered_rps:
          case List.last(passing) do
            nil -> nil
            {rate, _} -> rate
          end,
        all_tested_rates_pass: length(passing) == length(rates),
        rate_checks:
          Enum.map(rates, fn {rate, reps} ->
            %{
              offered_rps: rate,
              repetitions: length(reps),
              passing_repetitions: Enum.count(reps, & &1.budget_check.passes),
              reasons:
                Enum.flat_map(reps, & &1.budget_check.reasons) |> Enum.uniq() |> Enum.sort()
            }
          end)
      }
    end)
    |> Enum.sort_by(&{&1.workload, &1.connections, &1.client})
  end

  defp workload("small"), do: [bytes: 256, questions: 1]
  defp workload("batch"), do: [bytes: 16384, questions: 32]
  defp workload("mixed"), do: [bytes: 65536, questions: 1, large_every: 10]
  defp strings(opts, key, default), do: Keyword.get(opts, key, default) |> String.split(",")

  defp numbers(opts, key, default),
    do: strings(opts, key, default) |> Enum.map(&String.to_integer/1)

  defp write(output, report) do
    File.mkdir_p!(Path.dirname(output))
    File.write!(output <> ".tmp", JSON.encode!(report))
    File.rename!(output <> ".tmp", output)
  end
end
