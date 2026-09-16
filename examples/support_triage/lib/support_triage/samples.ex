defmodule SupportTriage.Samples do
  @moduledoc "Small illustrative fixtures, not an accuracy benchmark."

  def all do
    [
      %{
        id: "duplicate",
        title: "Duplicate charge",
        expected_department: "billing",
        message:
          "My invoice was charged twice yesterday. Both payments cleared. Please refund the extra payment.",
        follow_up:
          "The bigger issue is that your service is now down for our whole company. Nobody can work. Please restore it immediately; the refund can wait."
      },
      %{
        id: "outage",
        title: "Service outage",
        expected_department: "technical",
        message:
          "Your API has returned 503 for every request for the past hour. All our customer orders are blocked. We need help immediately.",
        follow_up: "The API is working again. Please explain what happened when you have time."
      },
      %{
        id: "ambiguous",
        title: "Ambiguous request",
        expected_department: "other",
        message: "Something is wrong with my account. Can someone help?",
        follow_up:
          "I mean I want to buy a bigger plan. Can sales explain enterprise pricing? Nothing is broken."
      },
      %{
        id: "sales",
        title: "Plan upgrade",
        expected_department: "sales",
        message:
          "We are considering your enterprise plan for 100 seats. Can your sales team explain pricing and arrange a demo?",
        follow_up: "We have no deadline; we are comparing options for next quarter."
      }
    ]
  end

  def fetch(id), do: Enum.find(all(), &(&1.id == id))
end
