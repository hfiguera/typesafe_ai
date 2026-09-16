defmodule TypeSafe.Response do
  @moduledoc "An evaluation's model, string-keyed typed answers, and token usage."
  alias TypeSafe.Answer.{Choice, Noul, Score}
  alias TypeSafe.Error

  @type t :: %__MODULE__{
          model: String.t(),
          answers: %{String.t() => Choice.t() | Score.t() | Noul.t()},
          usage: %{input_tokens: non_neg_integer(), output_tokens: non_neg_integer()}
        }
  @enforce_keys [:model, :answers, :usage]
  defstruct [:model, :answers, :usage]

  @doc "Decodes a response and checks that every requested question has a valid answer."
  @spec decode(binary(), map()) :: {:ok, t()} | {:error, Error.t()}
  def decode(body, schema) do
    with {:ok, %{"model" => model, "answers" => answers, "usage" => usage}} <- JSON.decode(body),
         true <- is_binary(model) and is_map(answers) and valid_usage?(usage),
         true <- Enum.sort(Map.keys(answers)) == Enum.sort(Map.keys(schema)),
         true <- Enum.all?(answers, fn {id, value} -> valid_answer?(value, schema[id]) end) do
      {:ok,
       %__MODULE__{
         model: model,
         answers: Map.new(answers, fn {id, a} -> {id, answer(a)} end),
         usage: %{input_tokens: usage["input_tokens"], output_tokens: usage["output_tokens"]}
       }}
    else
      _invalid -> {:error, Error.new(:invalid_response, "Invalid System One response")}
    end
  end

  defp valid_usage?(%{"input_tokens" => input, "output_tokens" => output}),
    do: is_integer(input) and input >= 0 and is_integer(output) and output >= 0

  defp valid_usage?(_usage), do: false

  defp valid_answer?(%{"type" => "noul", "noul" => value}, %{type: "noul"}),
    do: probability?(value)

  defp valid_answer?(
         %{
           "type" => "choice",
           "choice" => selected,
           "probabilities" => probs,
           "confidence" => confidence
         },
         %{type: "choice", criteria: criteria}
       ) do
    is_binary(selected) and Map.has_key?(criteria, selected) and probability?(confidence) and
      distribution?(probs, Map.keys(criteria))
  end

  defp valid_answer?(
         %{
           "type" => "score",
           "score" => score,
           "legend" => legend,
           "probabilities" => probs,
           "confidence" => confidence
         },
         %{type: "score", criteria: levels}
       ) do
    keys = Enum.map(0..(length(levels) - 1), &Integer.to_string/1)

    is_number(score) and score >= 0 and score <= length(levels) - 1 and
      probability?(confidence) and is_map(legend) and
      Enum.sort(Map.keys(legend)) == Enum.sort(keys) and
      distribution?(probs, keys)
  end

  defp valid_answer?(_answer, _schema), do: false

  defp distribution?(probs, keys) when is_map(probs) do
    values = Map.values(probs)

    Enum.sort(Map.keys(probs)) == Enum.sort(keys) and Enum.all?(values, &probability?/1) and
      abs(Enum.sum(values) - 1) < 0.02
  end

  defp distribution?(_probs, _keys), do: false
  defp probability?(value), do: is_number(value) and value >= 0 and value <= 1

  defp answer(%{"type" => "noul"} = a), do: %Noul{noul: a["noul"]}

  defp answer(%{"type" => "choice"} = a),
    do: %Choice{
      choice: a["choice"],
      probabilities: a["probabilities"],
      confidence: a["confidence"]
    }

  defp answer(%{"type" => "score"} = a),
    do: %Score{
      score: a["score"],
      probabilities: a["probabilities"],
      confidence: a["confidence"],
      legend: a["legend"]
    }
end
