defmodule SupportTriage.Evaluation.CLI do
  @moduledoc "Runs labeled evaluations and saves results before returning failure status."
  alias SupportTriage.Evaluation.{Dataset, Report, Runner}

  @usage """
  Usage: mix triage.eval [--dataset datasets/support.jsonl] [--output results/run.json]
                        [--model jev-latest] [--concurrency 1] [--timeout 30000]
                        [--confidence 0.65] [--probability 0.8]
                        [--missing-information 2.0] [--limit N]
  Requires TYPESAFE_API_KEY. Every message is one billable request, without retries.
  Final revisions are scored; all completed revisions contribute latency and tokens.
  """

  def run(args, runtime_opts \\ []) do
    with {:ok, flags} <- parse(args) do
      if flags[:help], do: IO.puts(@usage), else: evaluate(flags, runtime_opts)
    end
  end

  defp parse(args) do
    {flags, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          dataset: :string,
          output: :string,
          model: :string,
          concurrency: :integer,
          timeout: :integer,
          confidence: :float,
          probability: :float,
          missing_information: :float,
          limit: :integer,
          help: :boolean
        ]
      )

    if rest == [] and invalid == [] and valid?(flags) do
      {:ok, flags}
    else
      IO.puts(@usage)
      {:error, :invalid_arguments}
    end
  end

  defp valid?(flags) do
    limits = [
      {:confidence, 0, 1, 0.65},
      {:probability, 0, 1, 0.8},
      {:missing_information, 0, 3, 2.0},
      {:concurrency, 1, 4, 1},
      {:timeout, 1, 120_000, 30_000},
      {:limit, 1, 1_000_000, 1}
    ]

    Enum.all?(limits, fn {key, low, high, default} ->
      value = Keyword.get(flags, key, default)
      value >= low and value <= high
    end) and String.trim(Keyword.get(flags, :model, "jev-latest")) != ""
  end

  defp evaluate(flags, runtime_opts) do
    path = Keyword.get(flags, :dataset, "datasets/support.jsonl")
    output = Keyword.get_lazy(flags, :output, &default_output/0)
    client = Keyword.get(runtime_opts, :client, SupportTriage.Client)

    with {:ok, dataset} <- Dataset.load(path),
         :ok <- client_available(client),
         :ok <- prepare_output(output) do
      cases = Enum.take(dataset.cases, Keyword.get(flags, :limit, length(dataset.cases)))
      opts = options(flags, client)

      IO.puts(
        "Evaluating #{length(cases)} #{dataset.split} tickets (#{requests(cases)} possible requests)."
      )

      started_at = DateTime.to_iso8601(DateTime.utc_now())
      started = System.monotonic_time(:millisecond)
      results = Runner.run(cases, opts)

      report =
        Report.build(
          dataset,
          results,
          opts,
          started_at,
          System.monotonic_time(:millisecond) - started
        )

      finish(output, report)
    end
  end

  defp finish(output, report) do
    with :ok <- Report.save(output, report) do
      Report.print(report)
      IO.puts("Results saved to #{output}")
      if report.summary.failures == 0, do: :ok, else: {:error, :evaluation_failed}
    end
  end

  defp options(flags, client) do
    [
      client: client,
      model: Keyword.get(flags, :model, "jev-latest"),
      concurrency: Keyword.get(flags, :concurrency, 1),
      timeout: Keyword.get(flags, :timeout, 30_000),
      policy: [
        confidence: Keyword.get(flags, :confidence, 0.65),
        probability: Keyword.get(flags, :probability, 0.8),
        missing_information: Keyword.get(flags, :missing_information, 2.0)
      ]
    ]
  end

  defp client_available(client) do
    if GenServer.whereis(client), do: :ok, else: {:error, :missing_key}
  end

  defp prepare_output(path) do
    if File.exists?(path), do: {:error, :output_exists}, else: File.mkdir_p(Path.dirname(path))
  end

  defp default_output do
    suffix = Base.encode16(:crypto.strong_rand_bytes(5), case: :lower)
    "results/eval-#{System.system_time(:millisecond)}-#{suffix}.json"
  end

  defp requests(cases),
    do: Enum.reduce(cases, 0, fn row, acc -> acc + length(row["messages"]) end)
end
