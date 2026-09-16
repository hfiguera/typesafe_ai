# Errors and retries

`TypeSafe.system_one/2` returns either `{:ok, %TypeSafe.Response{}}` or
`{:error, %TypeSafe.Error{}}`. Match the error's `:kind` and optional `:status`;
message wording may change.

```elixir
case TypeSafe.system_one(MyApp.TypeSafe,
       state: "Please refund me",
       questions: %{"refund" => TypeSafe.noul("Refund requested?")}) do
  {:ok, response} ->
    {:ok, response.answers["refund"].noul}

  {:error, %TypeSafe.Error{kind: :http, status: 401}} ->
    {:error, :invalid_credentials}

  {:error, %TypeSafe.Error{kind: :overloaded}} ->
    {:error, :busy}

  {:error, %TypeSafe.Error{kind: :timeout}} ->
    {:error, :deadline_exceeded}

  {:error, %TypeSafe.Error{} = error} ->
    {:error, error}
end
```

## Failure categories

| Kind | Meaning and handling |
| --- | --- |
| `:configuration` | Invalid client options or retry policy. Fix configuration before trying again. |
| `:validation` | Invalid request options, question schema, or JSON input. Correct the input. |
| `:transport` | Connection, TLS, or socket failure. A submitted evaluation may already have been processed. |
| `:timeout` | The deadline expired, or the next retry delay would exhaust it. Check load and timing before resubmitting. |
| `:overloaded` | The client's outstanding request limit is reached. Apply backpressure or reduce concurrency. |
| `:http` | A non-success HTTP status after applying the retry policy. Inspect `:status`. |
| `:invalid_response` | Malformed JSON, inconsistent answers, or an oversized response. Not retried automatically. |
| `:unavailable` | The client process could not serve the call, including shutdown. Check supervision and registration. |

Invalid per-request retry policies produce `:configuration`; other invalid
evaluation options normally produce `:validation`. Local validation happens
before contacting the client. Ordinary evaluation failures are returned as
values, not raised exceptions.

## Default policy

Both `TypeSafe.Client.start_link/1` and `TypeSafe.system_one/2` accept `:retry` as
a keyword list or a validated `TypeSafe.Retry` struct. Defaults are:

```elixir
retry_policy = [
  max_attempts: 3,
  statuses: [429, 529],
  base_delay: 250,
  max_delay: 5_000,
  retry_transport: false
]
```

Pass it as `retry: retry_policy` in client or request options.
`:max_attempts` includes the initial submission and accepts 1–10. Use
`retry: [max_attempts: 1]` for a single attempt. Other non-success statuses are
returned immediately unless you explicitly add them to `:statuses`.

A per-request policy **replaces** the client policy. Omitted fields take the
library defaults, not the client values. For example, overriding only
`max_attempts: 2` also selects the default statuses and disables transport replay,
even if the client was configured differently.

Backoff selects a random delay from zero to the smaller of `:max_delay` and
`:base_delay * 2 ** (attempt - 1)`. A valid `Retry-After` header, expressed as
integer seconds or an HTTP date, takes precedence even above `:max_delay`.
Every attempt and wait shares the original deadline; it is never reset. If the
delay cannot fit in the remaining time, the call returns `:timeout` immediately.

## Transport replay

Failure to establish a connection is returned directly. Once a request has been
submitted, a transport failure is ambiguous: the service may already have
processed and billed the evaluation. The default policy does not replay it.
Enable `retry_transport: true` only when the application accepts that ambiguity.
The SDK does not provide an idempotency key or exactly-once guarantee.

Application-level retries create a **new** logical request with a new deadline.
Account for the client's own retry policy when adding retries around it. The
example application's interactive and evaluation commands use a single attempt.

## Diagnostics and privacy

Errors produced by the library exclude server bodies and low-level exception
details. They retain the HTTP status for HTTP errors. The library does not log
credentials, request state, or response bodies; formatted GenServer status is
redacted. Privileged process inspection such as `:sys.get_state/1` can still
access the process's actual memory.

`TypeSafe.Error.new/3` stores its supplied message unchanged; it does not redact
arbitrary strings. Use fixed descriptions if constructing your own errors.
For request timing, attempts, and outcomes without recording prompts, use
[telemetry](telemetry.md).
