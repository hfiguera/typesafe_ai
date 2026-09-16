defmodule SupportTriage.View do
  @moduledoc "Terminal presentation of actual answers, rules, and revision changes."
  alias TypeSafe.Answer.{Choice, Noul, Score}

  def show(entry, previous \\ nil) do
    IO.puts("\nRevision #{entry.revision}: #{entry.message}")

    case entry.result do
      {:ok, response} ->
        a = response.answers

        IO.puts(
          "Department: #{a["department"].choice} (confidence #{percent(a["department"].confidence)})"
        )

        IO.puts("Urgency: #{number(a["urgency"].score)} / 3")
        IO.puts("Refund requested: #{percent(a["refund_requested"].noul)}")
        IO.puts("Decision: #{entry.decision.route} [simulated]")
        IO.puts("Rule: #{entry.decision.rule}")

        IO.puts(
          "Model: #{response.model} | #{entry.duration_ms} ms | Tokens: #{response.usage.input_tokens} in / #{response.usage.output_tokens} out"
        )

        changes(previous, entry)

      {:error, error} ->
        IO.puts("Evaluation failed: #{error.kind}#{status(error.status)}. #{advice(error.kind)}")
        IO.puts("No new routing decision. Previous evaluations remain in history.")
    end
  end

  def all(%{result: {:ok, response}}) do
    response.answers
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.each(fn {id, answer} ->
      IO.puts("\n#{id}: #{value(answer)}")
      details(answer)
    end)
  end

  def all(_entry), do: IO.puts("This revision has no successful evaluation.")

  def history(agent) do
    Enum.each(agent.state.history, &show/1)
  end

  defp changes(%{result: {:ok, previous}} = before, %{result: {:ok, response}} = after_entry) do
    IO.puts("Changes since revision #{before.revision}:")

    Enum.each(Enum.sort(Map.keys(response.answers)), fn id ->
      old = value(previous.answers[id])
      new = value(response.answers[id])
      if old != new, do: IO.puts("  #{id}: #{old} → #{new}")
    end)

    IO.puts("  Route: #{before.decision.route} → #{after_entry.decision.route}")
  end

  defp changes(_before, _after), do: :ok

  defp details(%Noul{}), do: :ok

  defp details(answer) do
    IO.puts("  Confidence: #{percent(answer.confidence)}")

    Enum.each(Enum.sort(answer.probabilities), fn {label, probability} ->
      IO.puts("  #{label}: #{percent(probability)}#{legend(answer, label)}")
    end)
  end

  defp legend(%Score{legend: legend}, label), do: " — #{legend[label]}"
  defp legend(%Choice{}, _label), do: ""

  defp value(%Choice{choice: choice, confidence: confidence}),
    do: "#{choice} (confidence #{percent(confidence)})"

  defp value(%Score{score: score}), do: number(score)
  defp value(%Noul{noul: probability}), do: percent(probability)
  defp number(value), do: :erlang.float_to_binary(:erlang.float(value), decimals: 2)
  defp percent(value), do: number(value * 100) <> "%"
  defp status(nil), do: ""
  defp status(status), do: " (HTTP #{status})"

  defp advice(:http),
    do: "Check credentials or service status; requests are not retried automatically."

  defp advice(:timeout), do: "The request exceeded its deadline."
  defp advice(:overloaded), do: "The local client queue is full; reduce concurrent work."

  defp advice(:transport),
    do: "Check connectivity. The service may already have processed the request."

  defp advice(_kind), do: "Check the client configuration and try again when appropriate."
end
