defmodule TypeSafe.Error do
  @moduledoc """
  A failure returned as `{:error, error}` by the client.

  Match `:kind` and, for HTTP errors, `:status`; message text is descriptive and
  is not a stable identifier. The client returns these errors instead of raising
  them during normal evaluation.

  | Kind | Meaning |
  | --- | --- |
  | `:configuration` | Invalid client options or retry policy |
  | `:validation` | Invalid evaluation options, questions, or JSON input |
  | `:transport` | Connection, TLS, or socket failure |
  | `:timeout` | Overall deadline exhausted, or a retry cannot fit within it |
  | `:overloaded` | Client capacity and queue are full |
  | `:http` | Non-success HTTP response after the retry policy is applied |
  | `:invalid_response` | Malformed, inconsistent, or oversized response |
  | `:unavailable` | Client process unavailable or shutting down |

  Library-generated errors omit server bodies and low-level exception details,
  which can contain credentials or user input. `:status` retains an HTTP status
  for HTTP errors and is otherwise usually `nil`. This is not a general-purpose
  redaction facility: `new/3` preserves the message you supply.

  See the [errors and retries guide](guides/errors-and-retries.md) for handling examples.
  """
  @typedoc "Failure category; match this field instead of message text."
  @type kind ::
          :configuration
          | :validation
          | :transport
          | :timeout
          | :overloaded
          | :http
          | :invalid_response
          | :unavailable
  @typedoc "Failure category, descriptive message, and optional HTTP status."
  @type t :: %__MODULE__{kind: kind(), message: String.t(), status: pos_integer() | nil}
  defexception [:kind, :message, :status]

  @doc """
  Builds an error from the supplied description and optional HTTP status.

  The message is stored unchanged. Use a fixed description without credentials,
  request state, or response bodies when creating an error yourself.

  ## Examples

      iex> error = TypeSafe.Error.new(:http, "System One request failed", 401)
      iex> {error.kind, error.status, Exception.message(error)}
      {:http, 401, "System One request failed"}
  """
  @spec new(kind(), String.t(), pos_integer() | nil) :: t()
  def new(kind, message, status \\ nil),
    do: %__MODULE__{kind: kind, message: message, status: status}
end
