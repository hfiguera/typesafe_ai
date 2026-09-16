defmodule TypeSafe do
  @moduledoc """
  Evaluate a shared state with typed questions using TypeSafe AI.

  Start `TypeSafe.Client` in your supervision tree, then call `system_one/2`.
  Batch independent questions into one request; compose the answers in your code.
  """
  alias TypeSafe.{Client, Error, Question, Request, Response}

  @doc "Chooses one option from a map of string labels to descriptions."
  @spec choice(Question.entry(), map()) :: Question.t()
  def choice(instructions, criteria),
    do: %Question{type: :choice, instructions: instructions, criteria: criteria}

  @doc "Rates state against two to ten ordered, descriptive levels."
  @spec score(Question.entry(), [Question.entry()]) :: Question.t()
  def score(instructions, criteria),
    do: %Question{type: :score, instructions: instructions, criteria: criteria}

  @doc "Estimates P(yes), with optional string-keyed true/false descriptions."
  @spec noul(Question.entry(), map() | nil) :: Question.t()
  def noul(instructions, criteria \\ nil),
    do: %Question{type: :noul, instructions: instructions, criteria: criteria}

  @doc """
  Evaluates `:state` and a string-keyed `:questions` map.

  Optional overrides: `:model`, `:timeout` (overall milliseconds), and `:retry`
  (see `TypeSafe.Client`). The deadline includes queueing, connecting, and retries.
  """
  @spec system_one(GenServer.server(), keyword()) :: {:ok, Response.t()} | {:error, Error.t()}
  def system_one(client, opts) do
    with {:ok, request} <- Request.prepare(opts) do
      Client.evaluate(client, request)
    end
  end
end
