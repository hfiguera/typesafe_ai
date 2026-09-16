defmodule SupportTriage.Batch do
  @moduledoc "Runs sample tickets concurrently against the same supervised client."
  alias SupportTriage.Agent

  def run(samples, opts \\ []) do
    samples
    |> Task.async_stream(&evaluate(&1, opts),
      max_concurrency: 4,
      timeout: 35_000,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, _reason} -> %{error: :worker_failed}
    end)
  end

  defp evaluate(sample, opts) do
    case Agent.submit(Agent.new(), sample.message, opts) do
      {:ok, agent} -> %{sample: sample, entry: List.last(agent.state.history)}
      {:error, _reason} -> %{error: :workflow_failed}
    end
  end

  def report(results) do
    successful = Enum.filter(results, &success?/1)
    matches = Enum.count(successful, &matches?/1)

    Enum.each(results, &show/1)
    IO.puts("\nSuccessful evaluations: #{length(successful)}/#{length(results)}")

    IO.puts(
      "Expected department matches: #{matches}/#{length(results)} (includes failed evaluations)"
    )

    IO.puts("These illustrative labels are not a benchmark; probabilities and routes may vary.")

    tokens =
      Enum.reduce(successful, %{input_tokens: 0, output_tokens: 0}, fn result, acc ->
        {:ok, response} = result.entry.result

        %{
          input_tokens: acc.input_tokens + response.usage.input_tokens,
          output_tokens: acc.output_tokens + response.usage.output_tokens
        }
      end)

    IO.puts(
      "Total successful token usage: #{tokens.input_tokens} in / #{tokens.output_tokens} out"
    )

    if length(successful) == length(results), do: :ok, else: {:error, :batch_failed}
  end

  defp success?(%{entry: %{result: {:ok, _response}}}), do: true
  defp success?(_result), do: false

  defp matches?(%{sample: sample, entry: %{result: {:ok, response}}}),
    do: response.answers["department"].choice == sample.expected_department

  defp show(%{sample: sample, entry: entry}) do
    IO.puts("\n--- #{sample.title} (expected department: #{sample.expected_department}) ---")
    SupportTriage.View.show(entry)
  end

  defp show(%{error: _error}), do: IO.puts("\nSample worker failed; no decision was recorded.")
end
