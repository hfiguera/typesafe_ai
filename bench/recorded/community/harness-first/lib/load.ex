defmodule TypeSafe.Bench.Load do
  @moduledoc false
  alias TypeSafe.Bench.{Recordings, Runner, Transport}

  def run(args) do
    {opts, [], []} =
      OptionParser.parse(args,
        strict: [
          rate: :integer,
          profile: :string,
          requests: :integer,
          connections: :integer,
          max_in_flight: :integer,
          max_concurrency: :integer,
          max_queue: :integer,
          timeout: :integer,
          delay: :integer,
          client: :string,
          output: :string,
          large_every: :integer,
          bytes: :integer,
          questions: :integer,
          warmup: :integer,
          budget_ms: :integer,
          sample_storage: :string,
          recording: :string,
          recordings_dir: :string
        ]
      )

    report = measure(opts)
    output = Keyword.get(opts, :output, "results/load.json")
    File.mkdir_p!(Path.dirname(output))
    File.write!(output, JSON.encode!(report))
    IO.inspect(report, label: "Fixed arrival rate (driver drops are separate from client errors)")
    report
  end

  def measure(opts) do
    rate = Keyword.get(opts, :rate, 10_000)
    count = Keyword.get(opts, :requests, 20_000)
    limit = Keyword.get(opts, :max_in_flight, 512)
    budget = Keyword.get(opts, :budget_ms, 20)
    storage = Keyword.get(opts, :sample_storage, "ets")
    true = storage in ["ets", "list"]
    true = rate > 0 and count > 0 and limit > 0 and budget > 0

    recording =
      if id = opts[:recording] do
        true = Keyword.get(opts, :target, :offline) == :offline
        true = Keyword.get(opts, :large_every, 0) == 0

        opts
        |> Keyword.get(:recordings_dir, Recordings.default_path())
        |> Recordings.load()
        |> Map.fetch!(id)
      end

    scenario = %{
      client: Keyword.get(opts, :client, "typesafe"),
      profile: Keyword.get(opts, :profile, "matched"),
      protocol: if(Keyword.get(opts, :profile) == "defaults", do: :default, else: :http2),
      connections: Keyword.get(opts, :connections, 1),
      delay: Keyword.get(opts, :delay, 5),
      max_concurrency: Keyword.get(opts, :max_concurrency, 10),
      max_queue: Keyword.get(opts, :max_queue, 100),
      large_every: Keyword.get(opts, :large_every, 0),
      bytes: Keyword.get(opts, :bytes, 256),
      questions: Keyword.get(opts, :questions, 1),
      target: Keyword.get(opts, :target, :offline),
      model: Keyword.get(opts, :model, "jev-benchmark")
    }

    true = scenario.profile in ["matched", "defaults"]
    true = scenario.bytes > 0 and scenario.questions > 0 and scenario.connections > 0
    true = scenario.large_every >= 0 and scenario.max_concurrency > 0 and scenario.max_queue >= 0

    base = [
      state: String.duplicate("x", 256),
      questions: %{"q1" => TypeSafe.noul("True?")},
      retry: [max_attempts: 1],
      timeout: Keyword.get(opts, :timeout, 1000)
    ]

    regular =
      Keyword.merge(base,
        state: Keyword.get(opts, :state, String.duplicate("x", scenario.bytes)),
        questions:
          Map.new(
            1..scenario.questions,
            &{"q#{&1}", TypeSafe.noul(Keyword.get(opts, :question, "True?"))}
          )
      )

    regular = if recording, do: Keyword.merge(regular, recording.input), else: regular
    scenario = if recording, do: Map.put(scenario, :recording, recording), else: scenario

    input = %{
      small: Transport.input(scenario.client, base),
      regular: Transport.input(scenario.client, regular),
      large_every: scenario.large_every
    }

    warmup = Keyword.get(opts, :warmup, scenario.connections * 4)
    true = warmup > 0
    {call, stop} = Transport.start(scenario)

    try do
      # Readiness polling only retries local pool-not-started errors. Service errors
      # are never retried. Include warmup usage in live cost accounting.
      warmed =
        for _ <- 1..warmup do
          case Transport.ready(call, input.regular) do
            {:ok, response} ->
              metadata(response)

            {:error, _} ->
              raise "benchmark warmup failed; stopping without logging credentials or response bodies"
          end
        end

      :erlang.garbage_collect()
      before = Runner.snapshot()
      origin = System.monotonic_time(:microsecond)

      result =
        drive(call, input,
          rate: rate,
          requests: count,
          max_in_flight: limit,
          origin: origin,
          sample_storage: storage,
          snapshot: true
        )

      elapsed = result.finished_at - origin
      after_run = result.finished_snapshot
      good = for {latency, :ok, _lag, _kind, _meta} <- result.samples, do: latency
      scheduled = for {latency, :ok, lag, _kind, _meta} <- result.samples, do: latency + lag
      met = Enum.count(scheduled, &(&1 <= budget * 1000))
      meta = warmed ++ Enum.map(result.samples, &elem(&1, 4))

      # Body snapshots belong to the corpus, not each timing report. Usage below
      # is replayed metadata for recorded cases, never additional live consumption.
      summary_scenario =
        if recording do
          scenario
          |> Map.delete(:recording)
          |> Map.merge(%{
            recording_id: recording.id,
            request_sha256: recording.request_sha256,
            response_sha256: recording.response_sha256,
            request_body_bytes: recording.request_bytes,
            response_body_bytes: recording.response_bytes,
            bytes: JSON.encode!(regular[:state]) |> byte_size(),
            questions: map_size(regular[:questions]),
            model: recording.request["model"],
            usage_source: "recorded_response_replayed_not_live_usage"
          })
        else
          scenario
        end

      summary_scenario =
        if scenario.profile == "defaults" do
          Map.merge(summary_scenario, %{
            connections: if(scenario.client == "typesafe", do: 1, else: nil),
            max_concurrency: if(scenario.client == "typesafe", do: 10, else: nil),
            max_queue: if(scenario.client == "typesafe", do: 100, else: nil)
          })
        else
          summary_scenario
        end

      Map.merge(summary_scenario, %{
        offered_rps: rate,
        offered_requests: count,
        max_in_flight: limit,
        timeout_ms: base[:timeout],
        warmup_requests: warmup,
        budget_ms: budget,
        outcomes: Enum.frequencies_by(result.samples, &elem(&1, 1)),
        driver_dropped: result.dropped,
        sample_storage: storage,
        driver_memory_bytes_at_end: result.driver_memory_bytes_at_end,
        sample_table_bytes_at_end: result.sample_table_bytes_at_end,
        timeline: result.timeline,
        workloads: workload_results(result.samples),
        source_sha256: Runner.source_digest(),
        environment: Runner.environment(),
        driver_max_lag_ms: result.max_lag / 1000,
        driver_launch_lag_ms: Runner.percentiles(Enum.map(result.samples, &elem(&1, 2))),
        successful_rps_including_drain: length(good) * 1_000_000 / elapsed,
        success_latency_ms: Runner.percentiles(good),
        success_latency_from_scheduled_arrival_ms: Runner.percentiles(scheduled),
        successful_within_budget: met,
        within_budget_fraction_of_offered: met / count,
        elapsed_ms_including_drain: elapsed / 1000,
        offered_duration_ms: count * 1000 / rate,
        vm_cpu_ms: after_run.cpu - before.cpu,
        vm_reductions: after_run.reductions - before.reductions,
        vm_gc_count: after_run.gc - before.gc,
        vm_gc_words: after_run.words - before.words,
        vm_memory_before_bytes: before.memory,
        vm_memory_after_bytes: after_run.memory,
        models:
          meta |> Enum.map(& &1.model) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort(),
        observed_usage_including_warmup: %{
          input_tokens: Enum.sum(Enum.map(meta, & &1.input_tokens)),
          output_tokens: Enum.sum(Enum.map(meta, & &1.output_tokens))
        }
      })
    after
      stop.()
    end
  end

  # Public for deterministic driver tests without TLS or a real service.
  def drive(call, input, opts) do
    storage = Keyword.get(opts, :sample_storage, "ets")
    true = storage in ["ets", "list"]
    samples = if storage == "ets", do: :ets.new(__MODULE__, [:private, :set]), else: []

    try do
      result =
        loop(
          %{
            origin:
              Keyword.get_lazy(opts, :origin, fn -> System.monotonic_time(:microsecond) end),
            interval: 1_000_000 / Keyword.fetch!(opts, :rate),
            next: 0,
            count: Keyword.fetch!(opts, :requests),
            limit: Keyword.fetch!(opts, :max_in_flight),
            pending: %{},
            samples: samples,
            dropped: 0,
            drop_buckets: %{},
            max_lag: 0
          },
          call,
          input
        )

      # Stop the measurement clock before collecting/sorting samples. ETS keeps
      # the arrival scheduler's GC work bounded as the observation count grows.
      finished_at = System.monotonic_time(:microsecond)
      driver_memory = Process.info(self(), :memory) |> elem(1)

      table_bytes =
        if storage == "ets",
          do: :ets.info(samples, :memory) * :erlang.system_info(:wordsize),
          else: nil

      snapshot = if Keyword.get(opts, :snapshot, false), do: Runner.snapshot(), else: nil
      rows = if storage == "ets", do: :ets.tab2list(result.samples), else: result.samples

      %{result | samples: Enum.map(rows, &elem(&1, 1))}
      |> Map.put(:finished_at, finished_at)
      |> Map.put(:finished_snapshot, snapshot)
      |> Map.put(:driver_memory_bytes_at_end, driver_memory)
      |> Map.put(:sample_table_bytes_at_end, table_bytes)
      |> Map.put(:timeline, timeline(rows, result.drop_buckets, result.interval))
    after
      if storage == "ets", do: :ets.delete(samples)
    end
  end

  defp record_sample(state, index, sample) do
    if is_reference(state.samples) do
      true = :ets.insert(state.samples, {index, sample})
      state
    else
      %{state | samples: [{index, sample} | state.samples]}
    end
  end

  defp timeline(rows, drops, interval) do
    groups =
      Enum.group_by(rows, fn {index, _sample} -> div(round(index * interval), 1_000_000) end)

    (Map.keys(groups) ++ Map.keys(drops))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn second ->
      samples = Enum.map(Map.get(groups, second, []), &elem(&1, 1))

      %{
        second: second,
        offered_requests: length(samples) + Map.get(drops, second, 0),
        driver_dropped: Map.get(drops, second, 0),
        outcomes: Enum.frequencies_by(samples, &elem(&1, 1)),
        driver_launch_lag_ms: Runner.percentiles(Enum.map(samples, &elem(&1, 2))),
        success_latency_ms: Runner.percentiles(for {us, :ok, _, _, _} <- samples, do: us),
        success_latency_from_scheduled_arrival_ms:
          Runner.percentiles(for {us, :ok, lag, _, _} <- samples, do: us + lag)
      }
    end)
  end

  defp loop(%{next: count, count: count, pending: pending} = state, _call, _input)
       when map_size(pending) == 0, do: state

  defp loop(state, call, input) do
    # Consume completions before issuing overdue arrivals. Otherwise a busy
    # generator can count completed requests as in flight and falsely drop work.
    now = System.monotonic_time(:microsecond)
    due = state.origin + round(state.next * state.interval)
    wait = if state.next == state.count, do: 60_000, else: max(0, ceil((due - now) / 1000))

    receive do
      {:sample, pid, latency, outcome, finished, meta} ->
        {entry, pending} = Map.pop(state.pending, pid)
        Process.demonitor(entry.monitor, [:flush])
        sample = {latency, outcome, finished - latency - entry.planned, entry.kind, meta}
        loop(record_sample(%{state | pending: pending}, entry.index, sample), call, input)

      {:DOWN, _monitor, :process, pid, _reason} ->
        {entry, pending} = Map.pop(state.pending, pid)
        finished = System.monotonic_time(:microsecond)

        sample =
          {finished - entry.started, :driver_crash, entry.started - entry.planned, entry.kind,
           metadata(nil)}

        loop(record_sample(%{state | pending: pending}, entry.index, sample), call, input)
    after
      wait ->
        now = System.monotonic_time(:microsecond)

        if state.next < state.count and now >= due do
          loop(issue(state, call, input, now - due), call, input)
        else
          loop(state, call, input)
        end
    end
  end

  defp issue(state, call, input, lag) do
    state = %{state | next: state.next + 1, max_lag: max(state.max_lag, lag)}

    if map_size(state.pending) == state.limit do
      second = div(round((state.next - 1) * state.interval), 1_000_000)

      %{
        state
        | dropped: state.dropped + 1,
          drop_buckets: Map.update(state.drop_buckets, second, 1, &(&1 + 1))
      }
    else
      owner = self()

      kind =
        cond do
          input.large_every == 0 -> :regular
          rem(state.next, input.large_every) == 0 -> :large
          true -> :small
        end

      opts = if kind == :small, do: input.small, else: input.regular

      {pid, monitor} =
        spawn_monitor(fn ->
          {latency, result} = :timer.tc(fn -> call.(opts) end)
          finished = System.monotonic_time(:microsecond)

          {outcome, meta} =
            case result do
              {:ok, response} -> {:ok, metadata(response)}
              {:error, %{kind: kind}} -> {kind, metadata(nil)}
              {:error, _reason} -> {:transport, metadata(nil)}
            end

          send(owner, {:sample, self(), latency, outcome, finished, meta})
        end)

      entry = %{
        monitor: monitor,
        index: state.next - 1,
        kind: kind,
        started: System.monotonic_time(:microsecond),
        planned: state.origin + round((state.next - 1) * state.interval)
      }

      %{state | pending: Map.put(state.pending, pid, entry)}
    end
  end

  defp metadata(%ReqLLM.Response{} = response) do
    raw = response.provider_meta.raw_response

    %{
      model: raw["model"],
      input_tokens: raw["usage"]["input_tokens"] || 0,
      output_tokens: raw["usage"]["output_tokens"] || 0
    }
  end

  defp metadata(%TypeSafe.Response{} = response),
    do: Map.put(response.usage, :model, response.model)

  defp metadata(%{model: model, usage: %{input_tokens: input, output_tokens: output}}),
    do: %{model: model, input_tokens: input, output_tokens: output}

  defp metadata(_response), do: %{model: nil, input_tokens: 0, output_tokens: 0}

  defp workload_results(samples) do
    samples
    |> Enum.group_by(&elem(&1, 3))
    |> Map.new(fn {kind, rows} ->
      {kind,
       %{
         outcomes: Enum.frequencies_by(rows, &elem(&1, 1)),
         success_latency_ms: Runner.percentiles(for {us, :ok, _, _, _} <- rows, do: us),
         success_latency_from_scheduled_arrival_ms:
           Runner.percentiles(for {us, :ok, lag, _, _} <- rows, do: us + lag)
       }}
    end)
  end
end
