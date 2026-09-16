defmodule TypeSafe.Answer.Choice do
  @moduledoc """
  The answer to a question built with `TypeSafe.choice/2`.

  * `:choice` is the selected string label from the question's criteria.
  * `:probabilities` maps every criterion label to a number from 0 to 1.
  * `:confidence` is a number from 0 to 1 supplied by the service and derived
    from the distribution. It is distinct from the selected label's probability.

  These values are model outputs, not a measured guarantee of correctness.
  Choose routing thresholds using examples from your application.

  Given a response containing a question named `"team"`:

  ```elixir
  %TypeSafe.Answer.Choice{choice: team, probabilities: probabilities} =
    response.answers["team"]

  selected_probability = Map.fetch!(probabilities, team)
  ```
  """
  @typedoc "A string label and its complete probability distribution and confidence."
  @type t :: %__MODULE__{
          choice: String.t(),
          probabilities: %{String.t() => number()},
          confidence: number()
        }
  @enforce_keys [:choice, :probabilities, :confidence]
  defstruct [:choice, :probabilities, :confidence]
end

defmodule TypeSafe.Answer.Score do
  @moduledoc """
  The answer to a question built with `TypeSafe.score/2`.

  * `:score` is the probability-weighted level index. For `n` levels it ranges
    from 0 through `n - 1`, and may fall between levels.
  * `:probabilities` maps string indices such as `"0"` and `"1"` to probabilities.
  * `:legend` maps those same string indices to the service's level descriptions.
  * `:confidence` is a number from 0 to 1 derived by the service from the
    distribution, not an application-specific accuracy measurement.

  For levels `["Routine", "Today", "Immediately"]`, a score of `1.4` is between
  the second and third levels. It is not a percentage or a list index to pass
  directly to `Enum.at/2`. Use the distribution and your own thresholds to decide
  what action to take.
  """
  @typedoc "A score, string-indexed probabilities and legend, and confidence."
  @type t :: %__MODULE__{
          score: number(),
          probabilities: map(),
          legend: map(),
          confidence: number()
        }
  @enforce_keys [:score, :probabilities, :legend, :confidence]
  defstruct [:score, :probabilities, :legend, :confidence]
end

defmodule TypeSafe.Answer.Noul do
  @moduledoc """
  The answer to a question built with `TypeSafe.noul/2`.

  `:noul` is the probability of yes, from 0 to 1. There is no separate confidence
  field and no automatic Boolean conversion. Your application decides whether
  to act, ask for clarification, or request human review.

  ```elixir
  %TypeSafe.Answer.Noul{noul: probability} = response.answers["refund"]

  # An illustrative policy; choose a threshold using your own evaluation data.
  refund_requested? = probability >= 0.8
  ```
  """
  @typedoc "The service's probability of yes."
  @type t :: %__MODULE__{noul: number()}
  @enforce_keys [:noul]
  defstruct [:noul]
end
