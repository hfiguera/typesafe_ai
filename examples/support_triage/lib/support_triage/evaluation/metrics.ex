defmodule SupportTriage.Evaluation.Metrics do
  @moduledoc "Explicit denominators for model quality, routing quality, deferral, and failures."
  @automatic ~w(refund_review troubleshoot contact_sales incident_review)

  def score(%{error: nil, history: history, expected: expected}) do
    entry = List.last(history)
    {:ok, response} = entry.result
    action = entry.decision.action
    route_correct = action in expected["routes"]
    required = expected["requires_human_review"]
    automatic = action in @automatic

    %{
      department_correct: response.answers["department"].choice in expected["departments"],
      route_correct: route_correct,
      automatic: automatic,
      inappropriate_automatic: automatic and (not route_correct or required),
      review_required: required,
      review_satisfied: required and action == "human_review",
      disposition: disposition(action)
    }
  end

  def score(%{expected: expected}) do
    %{
      department_correct: false,
      route_correct: false,
      automatic: false,
      inappropriate_automatic: false,
      review_required: expected["requires_human_review"],
      review_satisfied: false,
      disposition: :failed
    }
  end

  def summarize(results) do
    scores = Enum.map(results, &score/1)
    total = length(results)
    automatic = count(scores, :automatic)
    requests = Enum.flat_map(results, & &1.history)
    successful = Enum.filter(requests, &match?({:ok, _response}, &1.result))

    %{
      cases: total,
      failures: Enum.count(results, &(not is_nil(&1.error))),
      department_correct: rate(count(scores, :department_correct), total),
      route_correct: rate(count(scores, :route_correct), total),
      automatic_coverage: rate(automatic, total),
      inappropriate_automatic: rate(count(scores, :inappropriate_automatic), automatic),
      required_review_recall:
        rate(count(scores, :review_satisfied), count(scores, :review_required)),
      dispositions: Enum.frequencies_by(scores, & &1.disposition),
      requests_recorded: length(requests),
      request_failures: length(requests) - length(successful),
      request_latency_ms: latency(Enum.map(requests, & &1.duration_ms)),
      successful_request_latency_ms: latency(Enum.map(successful, & &1.duration_ms)),
      case_latency_ms: latency(Enum.map(results, & &1.duration_ms)),
      tokens: tokens(successful)
    }
  end

  defp count(scores, field), do: Enum.count(scores, &Map.fetch!(&1, field))
  defp rate(_count, 0), do: %{count: 0, total: 0, fraction: nil}
  defp rate(count, total), do: %{count: count, total: total, fraction: count / total}
  defp disposition("clarify"), do: :clarification
  defp disposition("human_review"), do: :human_review
  defp disposition(_action), do: :automatic

  defp latency(values) do
    sorted = values |> Enum.reject(&is_nil/1) |> Enum.sort()
    %{count: length(sorted), median: median(sorted), p95: percentile(sorted, 0.95)}
  end

  defp median([]), do: nil

  defp median(sorted) do
    middle = div(length(sorted), 2)

    if rem(length(sorted), 2) == 0,
      do: (Enum.at(sorted, middle - 1) + Enum.at(sorted, middle)) / 2,
      else: Enum.at(sorted, middle)
  end

  defp percentile([], _fraction), do: nil
  defp percentile(sorted, fraction), do: Enum.at(sorted, ceil(length(sorted) * fraction) - 1)

  defp tokens(successful) do
    Enum.reduce(successful, %{input: 0, output: 0}, fn entry, acc ->
      {:ok, response} = entry.result

      %{
        input: acc.input + response.usage.input_tokens,
        output: acc.output + response.usage.output_tokens
      }
    end)
  end
end
