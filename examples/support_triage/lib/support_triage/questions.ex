defmodule SupportTriage.Questions do
  @moduledoc "Eleven independent questions, including speculative follow-up branches."

  def all do
    Map.merge(core(), branches())
  end

  defp core do
    %{
      "department" =>
        TypeSafe.choice("Which team owns the customer's current problem?", %{
          "billing" => "Charges, invoices, payments, and refunds",
          "technical" => "Broken software, outages, and integration failures",
          "sales" => "Plans, purchasing, upgrades, and pricing",
          "other" => "Unclear request or none of these teams"
        }),
      "request_type" =>
        TypeSafe.choice("What is the primary request?", %{
          "refund" => "Return or reverse a payment",
          "incident" => "Fix a service problem",
          "information" => "Answer a product or account question",
          "other" => "Something else or unclear"
        }),
      "next_action" =>
        TypeSafe.choice("What should a support worker do next?", %{
          "refund_review" => "Review a requested refund; do not issue money automatically",
          "troubleshoot" => "Investigate a technical problem",
          "contact_sales" => "Discuss product plans or purchasing",
          "clarify" => "Ask the customer for more information"
        }),
      "urgency" =>
        TypeSafe.score("How urgent is the current situation?", [
          "Routine; can wait",
          "Needs attention this week",
          "Needs attention today",
          "Immediate response needed; work is currently blocked"
        ]),
      "frustration" =>
        TypeSafe.score("How frustrated does the customer sound?", [
          "Calm",
          "Concerned",
          "Frustrated",
          "Very angry"
        ]),
      "missing_information" =>
        TypeSafe.score("How much essential information is missing?", [
          "Enough to choose a useful next step",
          "Minor details missing",
          "Important details needed before routing",
          "The problem itself is unclear"
        ]),
      "refund_requested" => TypeSafe.noul("Is the customer explicitly asking for a refund?"),
      "blocking_outage" =>
        TypeSafe.noul("Is an ongoing service failure blocking the customer's work?"),
      "human_review" =>
        TypeSafe.noul(
          "Does this need specialist human review beyond normal team routing because of " <>
            "conflicting requests, exceptional circumstances, or an unclear safe next step?"
        )
    }
  end

  defp branches do
    %{
      "refund_reason" =>
        TypeSafe.choice("If a refund is relevant, what is the reason?", %{
          "duplicate" => "Charged more than once",
          "cancellation" => "Cancelled or unwanted service",
          "service_failure" => "Paid service failed",
          "not_applicable" => "No refund or reason unclear"
        }),
      "failure_category" =>
        TypeSafe.choice("If a technical failure is relevant, what kind?", %{
          "outage" => "Service unavailable",
          "integration" => "API or integration problem",
          "account" => "Login or account access",
          "not_applicable" => "No failure or category unclear"
        })
    }
  end
end
