defmodule TypeSafe.Error do
  @moduledoc """
  A redacted client failure. `kind` distinguishes configuration, validation,
  transport, timeout, overload, HTTP, and response failures.

  Server bodies and socket exception details are deliberately omitted: either
  can contain credentials or user input. `status` retains an HTTP status when known.
  """
  @type kind ::
          :configuration
          | :validation
          | :transport
          | :timeout
          | :overloaded
          | :http
          | :invalid_response
          | :unavailable
  @type t :: %__MODULE__{kind: kind(), message: String.t(), status: pos_integer() | nil}
  defexception [:kind, :message, :status]

  @doc "Builds an error from a safe, fixed description."
  @spec new(kind(), String.t(), pos_integer() | nil) :: t()
  def new(kind, message, status \\ nil),
    do: %__MODULE__{kind: kind, message: message, status: status}
end
