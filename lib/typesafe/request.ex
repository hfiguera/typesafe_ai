defmodule TypeSafe.Request do
  @moduledoc false
  alias TypeSafe.{Error, Question, Retry}

  @spec prepare(term()) :: {:ok, map()} | {:error, Error.t()}
  def prepare(opts) when is_list(opts) do
    with :ok <- options(opts),
         {:ok, questions} <- Question.to_wire(Keyword.get(opts, :questions)),
         {:ok, state} <- state(opts),
         {:ok, retry} <- retry(Keyword.get(opts, :retry)) do
      {:ok,
       %{
         state: JSON.encode_to_iodata!(state),
         questions: JSON.encode_to_iodata!(questions),
         schema: questions,
         model: opts[:model],
         timeout: opts[:timeout],
         retry: retry,
         started: System.monotonic_time(:millisecond)
       }}
    end
  rescue
    Protocol.UndefinedError -> invalid()
    ArgumentError -> invalid()
  end

  def prepare(_opts), do: invalid()

  @spec body(map(), String.t()) :: iodata()
  def body(request, model) do
    [
      "{\"state\":",
      request.state,
      ",\"questions\":",
      request.questions,
      ",\"model\":",
      JSON.encode_to_iodata!(request.model || model),
      "}"
    ]
  end

  defp options(opts) do
    if Keyword.keyword?(opts) and
         Enum.all?(Keyword.keys(opts), &(&1 in [:state, :questions, :model, :timeout, :retry])) and
         model?(opts[:model]) and
         (is_nil(opts[:timeout]) or (is_integer(opts[:timeout]) and opts[:timeout] > 0)) do
      :ok
    else
      invalid()
    end
  end

  defp model?(nil), do: true
  defp model?(model), do: is_binary(model) and model != "" and String.valid?(model)

  defp state(opts) do
    case Keyword.fetch(opts, :state) do
      {:ok, value} when is_binary(value) or is_map(value) or is_list(value) -> {:ok, value}
      _other -> invalid()
    end
  end

  defp retry(nil), do: {:ok, nil}
  defp retry(value), do: Retry.new(value)
  defp invalid, do: {:error, Error.new(:validation, "Invalid request options or JSON input")}
end
