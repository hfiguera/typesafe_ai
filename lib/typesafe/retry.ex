defmodule TypeSafe.Retry do
  @moduledoc """
  Bounded retry policy. `max_attempts` includes the initial request.

  By default only explicit HTTP 429 and 529 responses are retried. Set
  `retry_transport: true` to permit replay after an ambiguous connection failure;
  the original evaluation may already have been processed and billed.
  """
  alias TypeSafe.Error

  @type t :: %__MODULE__{
          max_attempts: pos_integer(),
          base_delay: non_neg_integer(),
          max_delay: non_neg_integer(),
          statuses: [pos_integer()],
          retry_transport: boolean()
        }
  defstruct max_attempts: 3,
            base_delay: 250,
            max_delay: 5_000,
            statuses: [429, 529],
            retry_transport: false

  @doc "Validates a policy or keyword overrides."
  @spec new(term()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = policy) do
    if valid?(policy), do: {:ok, policy}, else: invalid()
  end

  def new(opts) when is_list(opts) do
    if Keyword.keyword?(opts) and
         Enum.all?(Keyword.keys(opts), &(Map.has_key?(%__MODULE__{}, &1) and &1 != :__struct__)) do
      new(struct(__MODULE__, opts))
    else
      invalid()
    end
  end

  def new(_opts), do: invalid()

  @doc "Returns a delay, honoring Retry-After seconds or an HTTP date when valid."
  @spec delay(t(), pos_integer(), [{String.t(), String.t()}]) :: non_neg_integer()
  def delay(policy, attempt, headers) do
    case Enum.find_value(headers, &retry_after/1) do
      nil -> jitter(policy, attempt)
      delay -> delay
    end
  end

  defp valid?(p) do
    valid_limits?(p) and
      is_boolean(p.retry_transport) and is_list(p.statuses) and
      Enum.all?(p.statuses, &(is_integer(&1) and &1 in 400..599))
  end

  defp valid_limits?(p) do
    is_integer(p.max_attempts) and p.max_attempts in 1..10 and
      is_integer(p.base_delay) and p.base_delay >= 0 and
      is_integer(p.max_delay) and p.max_delay >= p.base_delay
  end

  defp retry_after({"retry-after", value}), do: after_ms(value)
  defp retry_after(_header), do: nil

  defp after_ms(value) do
    case Integer.parse(value) do
      {seconds, ""} when seconds >= 0 -> seconds * 1_000
      _other -> date_delay(value)
    end
  end

  defp date_delay(value) do
    case :httpd_util.convert_request_date(String.to_charlist(value)) do
      {{_, _, _}, {_, _, _}} = date ->
        seconds =
          :calendar.datetime_to_gregorian_seconds(date) -
            :calendar.datetime_to_gregorian_seconds(:calendar.universal_time())

        max(seconds * 1_000, 0)

      _invalid ->
        nil
    end
  rescue
    ArgumentError -> nil
    FunctionClauseError -> nil
  end

  defp jitter(p, attempt) do
    ceiling = min(p.max_delay, p.base_delay * Integer.pow(2, attempt - 1))
    :rand.uniform(ceiling + 1) - 1
  end

  defp invalid, do: {:error, Error.new(:configuration, "Invalid retry policy")}
end
