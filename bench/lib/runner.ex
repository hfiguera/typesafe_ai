defmodule TypeSafe.Bench.Runner do
  @moduledoc false
  alias TypeSafe.Bench.Transport

  def run(args) do
    {opts, [], []} =
      OptionParser.parse(args,
        strict: [
          requests: :integer,
          repetitions: :integer,
          warmup: :integer,
          concurrency: :string,
          connections: :string,
          protocols: :string,
          delays: :string,
          payloads: :string,
          clients: :string,
          output: :string,
          label: :string,
          max_concurrency: :integer,
          max_queue: :integer,
          large_every: :integer
        ]
      )

    count = Keyword.get(opts, :requests, 2000)
    repetitions = Keyword.get(opts, :repetitions, 3)

    scenarios =
      for protocol <- strings(opts, :protocols, "http2,http1"),
          {bytes, questions} <- payloads(opts),
          delay <- numbers(opts, :delays, "0,5"),
          concurrency <- numbers(opts, :concurrency, "1,32,128"),
          connections <- numbers(opts, :connections, "1,2,4,8"),
          client <- strings(opts, :clients, "typesafe,finch,req,req_llm"),
          repetition <- 1..repetitions do
        %{
          protocol: %{"http1" => :http1, "http2" => :http2} |> Map.fetch!(protocol),
          bytes: bytes,
          questions: questions,
          delay: delay,
          concurrency: concurrency,
          connections: connections,
          client: client,
          repetition: repetition,
          requests: count,
          warmup: Keyword.get(opts, :warmup, 100),
          max_concurrency: Keyword.get(opts, :max_concurrency, 128),
          max_queue: Keyword.get(opts, :max_queue, 1024),
          large_every: Keyword.get(opts, :large_every, 0)
        }
      end

    # Randomized ordering avoids systematically favoring the client run first.
    results = scenarios |> Enum.shuffle() |> Enum.map(&measure/1)
    output = Keyword.get(opts, :output, "results/run.json")
    File.mkdir_p!(Path.dirname(output))

    File.write!(
      output,
      JSON.encode!(%{
        label: Keyword.get(opts, :label, "working-tree"),
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        environment: environment(),
        results: results
      })
    )

    IO.puts("Saved #{length(results)} scenarios to #{output}")
  end

  defp measure(scenario) do
    opts = [
      state: String.duplicate("x", scenario.bytes),
      questions: Map.new(1..scenario.questions, &{"q#{&1}", TypeSafe.noul("Is this true?")}),
      timeout: 30_000,
      retry: [max_attempts: 1]
    ]

    small =
      Transport.input(
        scenario.client,
        Keyword.merge(opts,
          state: String.duplicate("x", 256),
          questions: %{"q1" => TypeSafe.noul("Is this true?")}
        )
      )

    opts = Transport.input(scenario.client, opts)
    workload = %{regular: opts, small: small, large_every: scenario.large_every}
    {call, stop} = Transport.start(scenario)

    try do
      {cold_us, {:ok, _response}} = :timer.tc(fn -> Transport.ready(call, opts, 30_000) end)
      # Explicitly exercise all manually routed connections, then warm concurrent work.
      for _ <- 1..(scenario.connections * 4), do: {:ok, _response} = call.(opts)

      _warm =
        batch(
          call,
          workload,
          max(scenario.warmup, scenario.concurrency * 2),
          scenario.concurrency
        )

      :erlang.garbage_collect()
      before = snapshot()

      {elapsed_us, samples} =
        :timer.tc(fn -> batch(call, workload, scenario.requests, scenario.concurrency) end)

      after_run = snapshot()
      good = for {us, :ok, _kind} <- samples, do: us
      outcomes = Enum.frequencies_by(samples, &elem(&1, 1))

      result =
        Map.merge(scenario, %{
          elapsed_ms: elapsed_us / 1000,
          successful_rps: length(good) * 1_000_000 / elapsed_us,
          cold_first_ms: cold_us / 1000,
          outcomes: outcomes,
          workloads: workload_results(samples),
          success_latency_ms: percentiles(good),
          all_latency_ms: percentiles(Enum.map(samples, &elem(&1, 0))),
          vm_cpu_ms: after_run.cpu - before.cpu,
          vm_reductions: after_run.reductions - before.reductions,
          vm_gc_count: after_run.gc - before.gc,
          vm_gc_words: after_run.words - before.words,
          vm_memory_before_bytes: before.memory,
          vm_memory_after_bytes: after_run.memory
        })

      IO.puts(
        "#{scenario.client} #{scenario.protocol} pools=#{scenario.connections} c=#{scenario.concurrency} " <>
          "bytes=#{scenario.bytes} q=#{scenario.questions} delay=#{scenario.delay}: " <>
          "#{round(result.successful_rps)} ok/s p99=#{Float.round(result.success_latency_ms.p99 || 0.0, 2)}ms #{inspect(outcomes)}"
      )

      result
    after
      stop.()
    end
  end

  defp batch(call, workload, count, concurrency) do
    1..count
    |> Task.async_stream(
      fn index ->
        kind =
          cond do
            workload.large_every == 0 -> :regular
            rem(index, workload.large_every) == 0 -> :large
            true -> :small
          end

        opts = if kind == :small, do: workload.small, else: workload.regular
        {us, result} = :timer.tc(fn -> call.(opts) end)

        outcome =
          case result do
            {:ok, _response} -> :ok
            {:error, %{kind: kind}} -> kind
            {:error, _reason} -> :transport
          end

        {us, outcome, kind}
      end,
      max_concurrency: concurrency,
      ordered: false,
      timeout: 60_000
    )
    |> Enum.map(fn {:ok, sample} -> sample end)
  end

  defp workload_results(samples) do
    samples
    |> Enum.group_by(&elem(&1, 2))
    |> Map.new(fn {kind, samples} ->
      {kind,
       %{
         outcomes: Enum.frequencies_by(samples, &elem(&1, 1)),
         success_latency_ms: percentiles(for {us, :ok, _} <- samples, do: us)
       }}
    end)
  end

  def environment do
    %{
      source_sha256: source_digest(),
      harness_sha256: harness_digest(),
      lock_sha256: digest(["mix.lock"]),
      elixir: System.version(),
      otp: :erlang.system_info(:otp_release) |> to_string(),
      system: :erlang.system_info(:system_version) |> to_string(),
      schedulers: System.schedulers_online(),
      os: inspect(:os.type()),
      fixture:
        System.get_env(
          "BENCH_FIXTURE_DESCRIPTION",
          "separate BEAM on localhost; verified TLS; synthetic Noul answers"
        ),
      dependencies:
        Map.new(
          [
            :mint,
            :finch,
            :req,
            :req_llm,
            :jev,
            :typesafe_api,
            :typesafe_sdk,
            :pristine,
            :execution_plane_http,
            :jsv,
            :jason,
            :bandit
          ],
          &{&1, to_string(Application.spec(&1, :vsn))}
        )
    }
  end

  def source_digest do
    root = Mix.Project.deps_paths() |> Map.fetch!(:typesafe_ai) |> Path.expand()
    files = [Path.join(root, "mix.exs") | Path.wildcard(Path.join(root, "lib/**/*.ex"))]
    contents = Enum.map(Enum.sort(files), &[Path.relative_to(&1, root), "\0", File.read!(&1)])
    :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower)
  end

  def harness_digest do
    digest([
      "mix.exs",
      "mix.lock" | Path.wildcard("lib/**/*.ex") ++ Path.wildcard("config/*.exs")
    ])
  end

  defp digest(files) do
    files
    |> Enum.sort()
    |> Enum.map(&[&1, "\0", File.read!(&1)])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  def snapshot do
    {cpu, _} = :erlang.statistics(:runtime)
    {reductions, _} = :erlang.statistics(:reductions)
    {gc, words, _} = :erlang.statistics(:garbage_collection)
    %{cpu: cpu, reductions: reductions, gc: gc, words: words, memory: :erlang.memory(:total)}
  end

  def percentiles([]), do: %{p50: nil, p95: nil, p99: nil}

  def percentiles(samples) do
    sorted = Enum.sort(samples)

    Map.new([p50: 0.5, p95: 0.95, p99: 0.99], fn {key, fraction} ->
      {key, Enum.at(sorted, ceil(length(sorted) * fraction) - 1) / 1000}
    end)
  end

  defp strings(opts, key, default), do: Keyword.get(opts, key, default) |> String.split(",")

  defp numbers(opts, key, default),
    do: strings(opts, key, default) |> Enum.map(&String.to_integer/1)

  defp payloads(opts),
    do:
      strings(opts, :payloads, "256:1,16384:32")
      |> Enum.map(fn value ->
        [bytes, questions] = String.split(value, ":") |> Enum.map(&String.to_integer/1)
        {bytes, questions}
      end)
end
