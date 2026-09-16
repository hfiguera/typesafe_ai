defmodule SupportTriage.PolicyTest do
  use ExUnit.Case, async: true
  alias SupportTriage.{Fixture, Policy}

  test "routes the relevant speculative branch and never performs a refund" do
    decision = Policy.decide(Fixture.response())
    assert decision.action == "refund_review"
    assert decision.rule =~ "duplicate"

    technical =
      Fixture.response(%{
        "department" => "technical",
        "next_action" => "troubleshoot",
        "failure_category" => "integration"
      })

    assert Policy.decide(technical).rule =~ "integration"
  end

  test "uncertain, contradictory and incomplete evaluations get explicit fallback routes" do
    for {overrides, action} <- [
          {%{"confidence" => 0.64}, "human_review"},
          {%{"human_review" => 0.8}, "human_review"},
          {%{"missing_information" => 2.0}, "clarify"},
          {%{"department" => "technical", "next_action" => "refund_review"}, "human_review"},
          {%{"refund_requested" => 0.79}, "human_review"},
          {%{"department" => "sales", "next_action" => "contact_sales"}, "contact_sales"},
          {%{"next_action" => "clarify"}, "clarify"}
        ] do
      assert Policy.decide(Fixture.response(overrides)).action == action
    end
  end

  test "urgent blocking outages take precedence over normal routing" do
    response = Fixture.response(%{"blocking_outage" => 0.8, "urgency" => 2.0})
    assert Policy.decide(response).action == "incident_review"
  end

  test "thresholds can change routing without another model request" do
    response = Fixture.response(%{"confidence" => 0.65})
    assert Policy.decide(response).action == "refund_review"
    assert Policy.decide(response, confidence: 0.7).action == "human_review"
  end
end
