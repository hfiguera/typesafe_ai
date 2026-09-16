defmodule TypeSafe.Question do
  @moduledoc """
  A question about the request's shared state.

  Use `TypeSafe.choice/2`, `TypeSafe.score/2`, or `TypeSafe.noul/2` to construct
  questions. Instructions and descriptions accept strings, maps, or lists.
  Choice descriptions may also be nil when the label needs no explanation.
  Question IDs are string keys and are not used by the model for inference.
  """
  alias TypeSafe.Error

  @type entry :: String.t() | map() | list() | nil
  @type t :: %__MODULE__{type: :choice | :score | :noul, instructions: entry(), criteria: term()}
  @enforce_keys [:type, :instructions]
  defstruct [:type, :instructions, :criteria]

  @doc "Validates and converts a non-empty question map to its wire representation."
  @spec to_wire(term()) :: {:ok, map()} | {:error, Error.t()}
  def to_wire(questions) when is_map(questions) and map_size(questions) > 0 do
    if Enum.all?(questions, &valid_pair?/1) do
      {:ok, Map.new(questions, fn {id, q} -> {id, wire(q)} end)}
    else
      invalid()
    end
  end

  def to_wire(_questions), do: invalid()

  defp valid_pair?({id, %__MODULE__{} = q}) when is_binary(id) and byte_size(id) > 0,
    do: not is_nil(q.instructions) and entry?(q.instructions) and criteria?(q.type, q.criteria)

  defp valid_pair?(_pair), do: false

  defp criteria?(:choice, criteria) when is_map(criteria) and map_size(criteria) in 1..255 do
    Enum.all?(criteria, fn {key, value} -> is_binary(key) and key != "" and entry?(value) end)
  end

  defp criteria?(:score, criteria) when is_list(criteria),
    do: length(criteria) in 2..10 and Enum.all?(criteria, &entry?/1)

  defp criteria?(:noul, nil), do: true

  defp criteria?(:noul, criteria) when is_map(criteria) do
    Map.keys(criteria) |> Enum.sort() == ["false", "true"] and
      Enum.all?(criteria, fn {_key, value} -> entry?(value) end)
  end

  defp criteria?(_type, _criteria), do: false
  defp entry?(entry), do: is_nil(entry) or is_binary(entry) or is_map(entry) or is_list(entry)

  defp wire(%__MODULE__{type: :noul, criteria: nil} = q),
    do: %{type: "noul", instructions: q.instructions}

  defp wire(q),
    do: %{type: Atom.to_string(q.type), instructions: q.instructions, criteria: q.criteria}

  defp invalid,
    do: {:error, Error.new(:validation, "Invalid questions, instructions, or criteria")}
end
