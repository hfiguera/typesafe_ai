defmodule SupportTriage.EvaluationFixture do
  @moduledoc false
  alias SupportTriage.{Fixture, Policy}

  def ticket(id \\ "one") do
    %{
      "id" => id,
      "dataset_version" => "test-v1",
      "split" => "development",
      "tags" => ["clear"],
      "messages" => ["Private customer text"],
      "expected" => %{
        "departments" => ["billing"],
        "routes" => ["refund_review"],
        "requires_human_review" => false
      }
    }
  end

  def write(path, rows), do: File.write!(path, Enum.map(rows, &[JSON.encode!(&1), "\n"]))

  def result(id, overrides \\ %{}, duration \\ 10) do
    response = Fixture.response(overrides)

    %{
      id: id,
      expected: ticket()["expected"],
      tags: ["clear"],
      message_count: 1,
      error: nil,
      duration_ms: duration,
      history: [
        %{
          revision: 1,
          message: "Private customer text",
          duration_ms: duration,
          decision: Policy.decide(response),
          result: {:ok, response}
        }
      ]
    }
  end

  def failure(id \\ "failed", duration \\ 80) do
    result = result(id, %{}, duration)
    entry = hd(result.history)

    %{
      result
      | error: :timeout,
        history: [
          %{
            entry
            | decision: nil,
              result: {:error, TypeSafe.Error.new(:timeout, "Request deadline exceeded")}
          }
        ]
    }
  end
end
