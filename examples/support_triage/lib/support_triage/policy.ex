defmodule SupportTriage.Policy do
  @moduledoc "Explicit demo rules, with configurable thresholds; no external side effects."

  def decide(response, opts \\ []) do
    a = response.answers
    confidence = Keyword.get(opts, :confidence, 0.65)
    probability = Keyword.get(opts, :probability, 0.8)
    missing = Keyword.get(opts, :missing_information, 2.0)

    cond do
      a["department"].confidence < confidence or a["next_action"].confidence < confidence ->
        decision(
          "human_review",
          "Review queue",
          "Department or action confidence is below #{confidence}."
        )

      a["human_review"].noul >= probability ->
        decision(
          "human_review",
          "Review queue",
          "Specialist review probability reached #{probability}."
        )

      a["missing_information"].score >= missing ->
        decision("clarify", "Request details", "Missing-information score reached #{missing}.")

      a["blocking_outage"].noul >= probability and a["urgency"].score >= 2.0 ->
        decision(
          "incident_review",
          "Technical → urgent incident review",
          "Blocking-outage probability reached #{probability} and urgency is at least 2/3."
        )

      true ->
        route(a, probability)
    end
  end

  defp route(a, probability) do
    refund_probability = a["refund_requested"].noul

    case {a["department"].choice, a["next_action"].choice} do
      {"billing", "refund_review"} when refund_probability >= probability ->
        decision(
          "refund_review",
          "Billing → refund review",
          "Refund requested; reason: #{a["refund_reason"].choice}."
        )

      {"technical", "troubleshoot"} ->
        decision(
          "troubleshoot",
          "Technical → investigation",
          "Failure category: #{a["failure_category"].choice}."
        )

      {"sales", "contact_sales"} ->
        decision("contact_sales", "Sales → contact", "Department and next action agree on sales.")

      {_department, "clarify"} ->
        decision("clarify", "Request details", "Jev selected clarification as the next action.")

      _other ->
        decision(
          "human_review",
          "Review queue",
          "The evaluations do not match an automatic routing rule."
        )
    end
  end

  defp decision(action, route, rule), do: %{action: action, route: route, rule: rule}
end
