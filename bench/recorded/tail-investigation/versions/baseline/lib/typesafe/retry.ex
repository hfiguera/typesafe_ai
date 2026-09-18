defmodule TypeSafe.Retry do
  @moduledoc """
  Bounded retry policy. `max_attempts` includes the initial request.

  By default only explicit HTTP 429 and 529 responses are retried. Set
  `retry_transport: true` to permit replay after an ambiguous connection failure;
  the original evaluation may already have been processed and billed.

  Configure a policy with the client's `:retry` option or override it per call
  to `TypeSafe.system_one/2`. A per-call policy replaces the client policy;
  omitted fields take the defaults below. Setting `max_attempts: 1` disables
  retries. An initial connection failure is returned directly.

  | Field | Default | Accepted values |
  | --- | --- | --- |
  | `:max_attempts` | `3` | Integer from 1 to 10, including the first attempt |
  | `:base_delay` | `250` | Non-negative milliseconds |
  | `:max_delay` | `5_000` | Milliseconds, at least `:base_delay` |
  | `:statuses` | `[429, 529]` | List of HTTP status integers from 400 to 599 |
  | `:retry_transport` | `false` | Boolean; allow ambiguous transport replay |

  Backoff uses full jitter, capped by `:max_delay`. A valid `Retry-After` header
  takes precedence, including when longer than the cap. Retries share the
  original request deadline. If the next delay cannot fit, the client returns
  a timeout without waiting. See the [retry guide](guides/errors-and-retries.md).
  """
  alias TypeSafe.Error

  @typedoc "Validated attempt limits, backoff delays, and replay conditions."
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

  @doc """
  Validates a policy struct or builds one from keyword options.

  Unspecified fields use the struct defaults. Unknown options or invalid values
  return `{:error, %TypeSafe.Error{kind: :configuration}}`.

  ## Examples

      iex> {:ok, policy} = TypeSafe.Retry.new(max_attempts: 1)
      iex> {policy.max_attempts, policy.statuses, policy.retry_transport}
      {1, [429, 529], false}

      iex> {:error, error} = TypeSafe.Retry.new(max_attempts: 0)
      iex> error.kind
      :configuration
  """
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

  @doc """
  Calculates the delay in milliseconds after the given attempt.

  `policy` must be validated by `new/1`, and `attempt` is a positive integer:
  `1` means the initial request just failed. Header names must be lowercase,
  as returned by Mint. A valid `retry-after` value accepts non-negative integer
  seconds or an HTTP date. Invalid values fall back to jitter.

  Without a valid header, selects uniformly from zero through
  `min(max_delay, base_delay * 2 ** (attempt - 1))`, inclusive. This helper only
  computes a delay; the client separately enforces attempt and deadline limits.

  ## Examples

      iex> {:ok, policy} = TypeSafe.Retry.new([])
      iex> TypeSafe.Retry.delay(policy, 1, [{"retry-after", "8"}])
      8000
  """
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
