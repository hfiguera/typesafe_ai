defmodule SupportTriage.Evaluation.MetricsTest do
  use ExUnit.Case, async: true
  alias SupportTriage.Evaluation.Metrics
  alias SupportTriage.EvaluationFixture, as: Fixture

  test "separates model correctness, policy correctness, coverage, and failures" do
    correct = Fixture.result("correct")

    wrong =
      Fixture.result("wrong", %{"department" => "sales", "next_action" => "contact_sales"}, 20)

    review = Fixture.result("review", %{"human_review" => 0.9}, 40)

    review = %{
      review
      | expected: %{
          "departments" => ["billing", "other"],
          "routes" => ["human_review"],
          "requires_human_review" => true
        }
    }

    summary = Metrics.summarize([correct, wrong, review, Fixture.failure()])
    assert summary.department_correct == %{count: 2, total: 4, fraction: 0.5}
    assert summary.route_correct == %{count: 2, total: 4, fraction: 0.5}
    assert summary.automatic_coverage.fraction == 0.5
    assert summary.inappropriate_automatic == %{count: 1, total: 2, fraction: 0.5}
    assert summary.required_review_recall.fraction == 1.0
    assert summary.dispositions == %{automatic: 2, human_review: 1, failed: 1}
    assert summary.request_latency_ms == %{count: 4, median: 30.0, p95: 80}
    assert summary.successful_request_latency_ms == %{count: 3, median: 20, p95: 40}
    assert summary.tokens == %{input: 360, output: 90}
    assert summary.failures == 1
  end

  test "model can be correct while an overly cautious policy route is wrong" do
    result = Fixture.result("deferred", %{"confidence" => 0.1})
    scores = Metrics.score(result)
    assert scores.department_correct
    refute scores.route_correct
    refute scores.automatic
    assert scores.disposition == :human_review
  end

  test "a later failed revision cannot receive credit for an earlier correct answer" do
    earlier = Fixture.result("earlier")
    failed = Fixture.failure()
    result = %{failed | history: earlier.history ++ failed.history, message_count: 2}
    summary = Metrics.summarize([result])
    assert summary.route_correct.fraction == 0.0
    assert summary.requests_recorded == 2
    assert summary.request_failures == 1
    assert summary.tokens.input == 120
  end

  test "only final revisions are scored, while all successful usage is counted" do
    earlier = Fixture.result("earlier", %{"confidence" => 0.1})
    final = Fixture.result("final")
    result = %{final | history: earlier.history ++ final.history, message_count: 2}
    summary = Metrics.summarize([result])
    assert summary.route_correct.fraction == 1.0
    assert summary.tokens.input == 240
    assert summary.request_latency_ms.count == 2
  end

  test "empty denominators and unavailable worker timing are explicitly absent" do
    failed = %{Fixture.failure() | history: [], error: :worker_failed, duration_ms: nil}
    summary = Metrics.summarize([failed])
    assert summary.inappropriate_automatic.fraction == nil
    assert summary.required_review_recall.fraction == nil
    assert summary.case_latency_ms == %{count: 0, median: nil, p95: nil}
    assert summary.tokens == %{input: 0, output: 0}
  end

  test "p95 uses nearest rank rather than an arbitrary maximum" do
    results = Enum.map(1..20, &Fixture.result(Integer.to_string(&1), %{}, &1))
    summary = Metrics.summarize(results)
    assert summary.request_latency_ms.median == 10.5
    assert summary.request_latency_ms.p95 == 19
  end
end
