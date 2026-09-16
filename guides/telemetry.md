# Telemetry

The client emits events through `:telemetry`. No metrics backend is required;
attach handlers from your application to integrate with your logging or metrics
system. Events contain no request state, questions, bodies, headers, or keys.

## Event reference

| Event | Measurements | Metadata |
| --- | --- | --- |
| `[:typesafe, :request, :start]` | `system_time` in native time units | `request_id` |
| `[:typesafe, :request, :retry]` | `delay` in milliseconds; `attempt` just completed | `request_id`; `status` (HTTP integer or `nil`) |
| `[:typesafe, :request, :stop]` | `duration` in milliseconds; `attempts`; `input_tokens` and `output_tokens` on success | `request_id`; `outcome` |

`:request_id` is an Erlang reference identifying a logical request, shared across
its attempts. It is not a service request ID or a serializable identifier.
`:outcome` is `:ok`, an error kind from `TypeSafe.Error`, or `:cancelled` when the
caller exits. Attempts may be zero when work ends before any HTTP submission.

Accepted requests normally emit one start and one stop, including handled caller
cancellation and orderly client shutdown. Abrupt process termination may prevent
a stop event. Invalid input and queue overflow produce no request lifecycle
events. A retry event is emitted only when another attempt is scheduled.

Duration includes queueing, connection setup, uploads, response collection, and
retry waits after input encoding. **It is already in milliseconds**, unlike the
start event's native-unit timestamp. Do not apply native-unit conversion to it.
Token counts describe the successful attempt only, not total billable usage
across retries or failed requests.

## Attach a handler

Define a module in your application:

```elixir
defmodule MyApp.TypeSafeTelemetry do
  require Logger

  def attach do
    :telemetry.attach(
      "my-app-typesafe-stop",
      [:typesafe, :request, :stop],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event([:typesafe, :request, :stop], measurements, metadata, _config) do
    Logger.info("TypeSafe evaluation finished",
      typesafe_outcome: metadata.outcome,
      duration_ms: measurements.duration,
      attempts: measurements.attempts,
      input_tokens: Map.get(measurements, :input_tokens),
      output_tokens: Map.get(measurements, :output_tokens)
    )
  end
end
```

Call `MyApp.TypeSafeTelemetry.attach/0` once during application startup, before
starting the client. Handler IDs must be unique; attaching the same ID twice
returns `{:error, :already_exists}`. Use
`:telemetry.detach("my-app-typesafe-stop")` to remove this handler, for example
when experimenting in IEx. Configure your Logger formatter to display the
metadata fields you want to see.

Handlers execute synchronously in the emitting process. Keep them fast and
nonblocking; do not perform network calls or invoke the same TypeSafe client
inside a handler. Telemetry detaches a handler that fails. For metrics, aggregate
by low-cardinality outcome values rather than the unique request reference.
