defmodule TypeSafe do
  @moduledoc """
  Evaluate shared state with Choice, Score, and Noul questions using TypeSafe AI.

  Start a `TypeSafe.Client` under your application's supervisor, then call
  `system_one/2`. The client handles authentication, connection reuse, deadlines,
  and bounded retries. You receive `TypeSafe.Response` and typed answer structs.
  Elixir 1.18+ and Erlang/OTP 27+ are required; encoding uses native `JSON`.

  ## Example

  With a client registered as `MyApp.TypeSafe`:

  ```elixir
  TypeSafe.system_one(MyApp.TypeSafe,
    state: %{message: "Please refund the duplicate charge."},
    questions: %{
      "team" => TypeSafe.choice("Which team?", %{"billing" => nil, "technical" => nil}),
      "refund" => TypeSafe.noul("Is a refund requested?")
    }
  )
  ```

  Batch independent questions about the same state in one call. For separate
  states, use bounded tasks sharing a supervised client. See the
  [getting started guide](guides/getting-started.md) for complete setup, and
  `TypeSafe.Client` for capacity and lifecycle behavior.
  """
  alias TypeSafe.{Client, Error, Question, Request, Response}

  @doc """
  Builds a Choice question with 1–255 named options.

  `instructions` can be a string, JSON-compatible map, or list. `criteria` is a
  map of non-empty string labels to descriptions; a description may be a string,
  map, list, or `nil` when the label needs no explanation.

  Construction performs no network I/O or validation. `system_one/2` validates
  the question before submitting it. Answers use `TypeSafe.Answer.Choice`.

  ## Examples

      iex> question = TypeSafe.choice("Which team?", %{"billing" => "Payments", "technical" => nil})
      iex> question.type
      :choice
      iex> question.criteria["billing"]
      "Payments"
  """
  @doc group: "Question helpers"
  @spec choice(Question.entry(), map()) :: Question.t()
  def choice(instructions, criteria),
    do: %Question{type: :choice, instructions: instructions, criteria: criteria}

  @doc """
  Builds a Score question with 2–10 ordered descriptive levels.

  Level indices start at zero. A returned score is probability-weighted and may
  fall between levels; with three levels its range is 0–2, not 0–1 or 0–3.
  Instructions and level descriptions can contain structured JSON values.

  Questions are validated by `system_one/2`. Answers use `TypeSafe.Answer.Score`.

  ## Examples

      iex> question = TypeSafe.score("How urgent?", ["Routine", "Today", "Immediately"])
      iex> question.type
      :score
      iex> Enum.at(question.criteria, 2)
      "Immediately"
  """
  @doc group: "Question helpers"
  @spec score(Question.entry(), [Question.entry()]) :: Question.t()
  def score(instructions, criteria),
    do: %Question{type: :score, instructions: instructions, criteria: criteria}

  @doc """
  Builds a Noul question, whose answer estimates the probability of yes.

  Optional criteria must contain exactly the string keys `"true"` and `"false"`.
  Omit criteria when the instructions alone explain the decision. The returned
  `TypeSafe.Answer.Noul` contains a value from 0 to 1, without a separate confidence.
  The caller chooses any threshold used to turn that probability into a decision.

  ## Examples

      iex> question = TypeSafe.noul("Is a refund requested?")
      iex> {question.type, question.criteria}
      {:noul, nil}

      iex> question = TypeSafe.noul("Urgent?", %{"true" => "Work is blocked", "false" => "Can wait"})
      iex> question.criteria["true"]
      "Work is blocked"
  """
  @doc group: "Question helpers"
  @spec noul(Question.entry(), map() | nil) :: Question.t()
  def noul(instructions, criteria \\ nil),
    do: %Question{type: :noul, instructions: instructions, criteria: criteria}

  @doc """
  Evaluates state and returns `{:ok, response}` or `{:error, error}`.

  `client` is a PID or registered name accepted by `GenServer.call/3`.

  ## Options

  * `:state` (required) — a string, map, or list of JSON-compatible values.
  * `:questions` (required) — a non-empty map from non-empty string IDs to
    `TypeSafe.Question` structs built with the question helpers.
  * `:model` — a non-empty model identifier overriding the client default.
  * `:timeout` — a positive overall deadline in milliseconds, overriding the
    client default. It starts after input encoding and includes queueing,
    connecting, uploads, response collection, and retry waits.
  * `:retry` — a `TypeSafe.Retry` struct or keyword policy. An override replaces
    the client policy; omitted fields use the retry defaults. Set
    `retry: [max_attempts: 1]` to disable retries.

  Unknown options are rejected. API keys are configured per client, never per
  request. Invalid questions or unencodable inputs produce validation errors
  before contacting the client. Custom structs require a native `JSON.Encoder`
  implementation or conversion to plain JSON-compatible data.

  Successful answers preserve question IDs and option labels as strings. The
  response type depends on each question; see `TypeSafe.Response`. Match
  the `:kind` and `:status` fields of `TypeSafe.Error` for failures, rather than
  matching message text. An ambiguous transport failure is not retried by default.

  ## Examples

  Invalid input is rejected without accessing a client:

      iex> {:error, error} = TypeSafe.system_one(:unused_client, state: "Hello", questions: %{})
      iex> error.kind
      :validation
  """
  @doc group: "Evaluation"
  @spec system_one(GenServer.server(), keyword()) :: {:ok, Response.t()} | {:error, Error.t()}
  def system_one(client, opts) do
    with {:ok, request} <- Request.prepare(opts) do
      Client.evaluate(client, request)
    end
  end
end
