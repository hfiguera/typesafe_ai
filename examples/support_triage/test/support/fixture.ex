defmodule SupportTriage.Fixture do
  @moduledoc false

  def body(overrides \\ %{}) do
    answers =
      Map.new(SupportTriage.Questions.all(), fn {id, question} ->
        {id, answer(id, question, overrides)}
      end)

    JSON.encode!(%{
      model: "offline-fixture",
      answers: answers,
      usage: %{input_tokens: 120, output_tokens: 30}
    })
  end

  def response(overrides \\ %{}) do
    {:ok, schema} = TypeSafe.Question.to_wire(SupportTriage.Questions.all())
    {:ok, response} = TypeSafe.Response.decode(body(overrides), schema)
    response
  end

  defp answer(id, %{type: :choice, criteria: criteria}, overrides) do
    defaults = %{
      "department" => "billing",
      "next_action" => "refund_review",
      "refund_reason" => "duplicate"
    }

    selected = Map.get(overrides, id, Map.get(defaults, id, hd(Enum.sort(Map.keys(criteria)))))

    probabilities =
      Map.new(criteria, fn {key, _description} ->
        {key, if(key == selected, do: 0.95, else: 0.05 / (map_size(criteria) - 1))}
      end)

    %{
      type: "choice",
      choice: selected,
      probabilities: probabilities,
      confidence: Map.get(overrides, "confidence", 0.9)
    }
  end

  defp answer(id, %{type: :score, criteria: criteria}, overrides) do
    score = Map.get(overrides, id, 0.0)

    legend =
      criteria
      |> Enum.with_index()
      |> Map.new(fn {value, index} -> {Integer.to_string(index), value} end)

    probabilities =
      Map.new(legend, fn {key, _description} ->
        {key, max(0.0, 1.0 - abs(String.to_integer(key) - score))}
      end)

    %{type: "score", score: score, legend: legend, probabilities: probabilities, confidence: 0.9}
  end

  defp answer(id, %{type: :noul}, overrides) do
    default = if id == "refund_requested", do: 0.95, else: 0.05
    %{type: "noul", noul: Map.get(overrides, id, default)}
  end
end
