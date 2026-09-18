defmodule TypeSafe.Response do
  @moduledoc """
  A successful evaluation returned by `TypeSafe.system_one/2`.

  * `:model` is the actual model identifier returned by the service, which may
    differ from an alias supplied in the request.
  * `:answers` maps the original string question IDs to `TypeSafe.Answer.Choice`,
    `TypeSafe.Answer.Score`, or `TypeSafe.Answer.Noul` structs.
  * `:usage` contains `:input_tokens` and `:output_tokens`, non-negative integers
    reported for this successful evaluation. It does not aggregate prior attempts
    or provide billing information for failed requests.

  Each requested question must have an answer of the matching type. The client
  rejects missing/extra answers, invalid values, or inconsistent probability
  keys as `:invalid_response`. Dynamic IDs and labels remain strings.

  ```elixir
  case TypeSafe.system_one(MyApp.TypeSafe,
         state: "Please refund me",
         questions: %{"refund" => TypeSafe.noul("Refund requested?")}) do
    {:ok, %TypeSafe.Response{answers: %{"refund" => answer}}} -> answer.noul
    {:error, %TypeSafe.Error{kind: kind}} -> {:failed, kind}
  end
  ```
  """
  alias TypeSafe.Answer.{Choice, Noul, Score}
  alias TypeSafe.Error

  @typedoc "Model, typed answers, and token usage for one successful attempt."
  @type t :: %__MODULE__{
          model: String.t(),
          answers: %{String.t() => Choice.t() | Score.t() | Noul.t()},
          usage: %{input_tokens: non_neg_integer(), output_tokens: non_neg_integer()}
        }
  @enforce_keys [:model, :answers, :usage]
  defstruct [:model, :answers, :usage]

  @doc """
  Decodes a complete JSON response against a validated question schema.

  Obtain `schema` from `TypeSafe.Question.to_wire/1`; it uses atom field keys,
  not the string field keys produced by decoding a request's JSON. Normal client
  calls handle decoding automatically.

  Validates required fields, answer types, value ranges, and distribution keys.
  Probability sums tolerate rounding within 0.02 of 1. Returns a typed response
  or `{:error, %TypeSafe.Error{kind: :invalid_response}}`, omitting the raw body.

  ## Examples

      iex> {:ok, schema} = TypeSafe.Question.to_wire(%{"refund" => TypeSafe.noul("Refund requested?")})
      iex> body = ~s({"model":"jev-example","answers":{"refund":{"type":"noul","noul":0.9}},"usage":{"input_tokens":10,"output_tokens":2}})
      iex> {:ok, response} = TypeSafe.Response.decode(body, schema)
      iex> response.answers["refund"].noul
      0.9
      iex> response.usage
      %{input_tokens: 10, output_tokens: 2}
  """
  @doc group: "Advanced integration"
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
