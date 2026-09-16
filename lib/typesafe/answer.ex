defmodule TypeSafe.Answer.Choice do
  @moduledoc "The selected label, distribution, and distribution-derived confidence."
  @type t :: %__MODULE__{
          choice: String.t(),
          probabilities: %{String.t() => number()},
          confidence: number()
        }
  @enforce_keys [:choice, :probabilities, :confidence]
  defstruct [:choice, :probabilities, :confidence]
end

defmodule TypeSafe.Answer.Score do
  @moduledoc "A weighted level index with string-keyed probabilities and legend."
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
  @moduledoc "The probability of yes, without a separate confidence field."
  @type t :: %__MODULE__{noul: number()}
  @enforce_keys [:noul]
  defstruct [:noul]
end
