# TypeSafe for Elixir

An Elixir client for the [TypeSafe AI](https://docs.typesafe.ai) System One API.
Evaluate one shared state with Choice, Score, and Noul questions, and receive
typed answers. Uses Mint directly, native `JSON`, and a supervised connection
owner with bounded concurrency, queueing, deadlines, and retries.

Requires **Elixir 1.18+ and Erlang/OTP 27+**. Package/application: `typesafe_ai`;
module namespace: `TypeSafe`. This is an unreleased, independently maintained
client. Publishing and a license choice are still pending.

## Installation and supervision

While developing locally, add the project by path:

```elixir
{:typesafe_ai, path: "../typesafe"}
```

Start a client under your application's supervisor:

```elixir
children = [
  {TypeSafe.Client,
   name: MyApp.TypeSafe,
   api_key: System.fetch_env!("TYPESAFE_API_KEY"),
   model: "jev-latest"}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

The application retrieves the key and passes it explicitly. The library does
not read environment variables or Keychain. Separate clients can use different
keys; use `Supervisor.child_spec/2` with distinct `:id` values when starting
multiple clients under one supervisor. Connections are established lazily.

## Evaluate state

```elixir
{:ok, response} =
  TypeSafe.system_one(MyApp.TypeSafe,
    state: %{message: "I was charged twice. Please refund me."},
    questions: %{
      "team" =>
        TypeSafe.choice("Which team should handle this?", %{
          "billing" => "Payments, invoices, and refunds",
          "technical" => "Bugs and integration problems"
        }),
      "urgency" =>
        TypeSafe.score("How urgently should we respond?", [
          "Can wait until next week",
          "Needs attention today"
        ]),
      "refund" => TypeSafe.noul("Does the customer request a refund?")
    },
    timeout: 15_000
  )

%TypeSafe.Answer.Choice{choice: team, confidence: confidence} = response.answers["team"]
%TypeSafe.Answer.Score{score: urgency} = response.answers["urgency"]
%TypeSafe.Answer.Noul{noul: refund_probability} = response.answers["refund"]

response.model
response.usage # %{input_tokens: ..., output_tokens: ...}
```

Question IDs, Choice labels, probability keys, and Score legend keys stay strings.
No atoms are created from server input. Choice includes a full probability map.
Score includes probabilities and a legend; its value ranges from zero to the
last level's index and can fall between levels. Noul is a probability from 0 to
1 and has no separate confidence field. Choose application thresholds yourself.

State accepts a string, map, or list of JSON-compatible values. Instructions and
criteria descriptions may be structured maps or lists. Choice permits 1–255
options, including `nil` descriptions; Score requires 2–10 ordered levels. Noul
optionally accepts `%{"true" => "Yes means …", "false" => "No means …"}` as its
second argument. Helpers construct questions; `system_one/2` validates them.
Custom structs need conversion or a native `JSON.Encoder` implementation;
`Jason.Encoder` does not apply.

Batch independent questions about the same state in one evaluation. For different
states, use `Task.async_stream/3` with bounded concurrency. Calls return
`{:ok, %TypeSafe.Response{}}` or `{:error, %TypeSafe.Error{}}`.

## Configuration

| Client option | Default | Meaning |
| --- | --- | --- |
| `api_key` | Required | Non-empty Bearer credential |
| `name` | Unnamed | GenServer registration name |
| `base_url` | `https://api.typesafe.ai` | Endpoint root; optional path prefix |
| `model` | `jev-latest` | Model for evaluations |
| `timeout` | `30_000` | Overall request deadline in milliseconds |
| `connect_timeout` | `5_000` | Connection establishment timeout in milliseconds |
| `max_concurrency` | `10` | Maximum concurrent HTTP/2 streams |
| `max_queue` | `100` | Additional outstanding request slots |
| `max_response_bytes` | `8_388_608` | Maximum body bytes per response |
| `protocols` | `[:http1, :http2]` | Protocols Mint may negotiate |
| `transport_opts` | `[]` | `cacerts`, `cacertfile`, or TLS `versions` |
| `retry` | See below | Retry policy struct or keyword list |

Per-request options are `state`, `questions`, `model`, `timeout`, and `retry`.
Unknown options are rejected. Endpoint, authentication, and transport limits
belong to the client. TLS verifies certificates and hostnames using OTP's system
CA store by default; there is no option to disable verification. Plain HTTP is
supported for local fixtures or explicitly configured endpoints.

Each client owns one reusable connection. HTTP/1 runs one request at a time;
HTTP/2 respects both the client limit and the peer's stream limit. Outstanding
work, including retry waits, is bounded by the current protocol capacity plus
`max_queue`. Before negotiation, capacity is conservatively one. Excess work
returns `:overloaded` immediately.

The deadline starts after input validation/encoding and includes queueing,
connection establishment, uploads, response collection, and retry waits. Socket
sends have a one-second upper timeout; scheduling or a blocked send can delay
delivery of a timeout result. A dead caller releases its slot. HTTP/1 cancellation
closes the connection; HTTP/2 cancellation resets only that stream. Subsequent
work reconnects as needed. There is no connection pool or WebSocket transport.

## Retries and errors

The default policy is:

```elixir
retry: [
  max_attempts: 3,
  statuses: [429, 529],
  base_delay: 250,
  max_delay: 5_000,
  retry_transport: false
]
```

Attempts include the initial request and are limited to 1–10. Delays use capped
exponential backoff with full jitter. A valid `Retry-After` value (seconds or HTTP
date) takes precedence, even above `max_delay`. If the delay cannot fit within
the remaining deadline, the client returns `:timeout` immediately.

Use `retry: [max_attempts: 1]` to disable retries. A per-request policy replaces
the client policy; omitted fields use the policy defaults. Transport failures
after submission are ambiguous: the server may already have processed and billed
the evaluation. Replay requires explicit `retry_transport: true`. Failure to
establish a connection returns a transport error directly. Permanent HTTP errors
are returned without replay unless their status was explicitly added to the policy.

```elixir
case TypeSafe.system_one(MyApp.TypeSafe, state: "Hello", questions: %{
       "greeting" => TypeSafe.noul("Is this a greeting?")
     }) do
  {:ok, response} -> response.answers["greeting"].noul
  {:error, %TypeSafe.Error{kind: :http, status: 401}} -> :invalid_credentials
  {:error, %TypeSafe.Error{kind: :timeout}} -> :deadline_exceeded
  {:error, %TypeSafe.Error{kind: kind}} -> {:failed, kind}
end
```

Error kinds are `:configuration`, `:validation`, `:transport`, `:timeout`,
`:overloaded`, `:http`, `:invalid_response`, and `:unavailable`. Errors retain HTTP
status where applicable, but omit server bodies and low-level exception details.
The library does not log keys, request state, or response bodies. Formatted
GenServer status is redacted. As with any BEAM process, privileged debugging
such as `:sys.get_state/1` can access its actual memory.

## Telemetry

Events use the prefix `[:typesafe, :request]`:

| Suffix | Measurements | Metadata |
| --- | --- | --- |
| `:start` | `system_time` in native units | `request_id` reference |
| `:retry` | `delay` in ms, `attempt` | `request_id`, HTTP `status` or nil |
| `:stop` | `duration` in ms, `attempts`; token counts on success | `request_id`, `outcome` |

Each accepted logical request has one start and stop, including caller
cancellation (`:cancelled`) and client shutdown (`:unavailable`). Rejected input
and queue overflow do not emit lifecycle events. Other stop outcomes are `:ok`
or an error kind. Metadata contains no prompts, bodies, headers, or credentials.
Handlers execute synchronously; keep them fast and nonblocking.

## Development

The `examples/support_triage` application demonstrates a Jido support decision
agent using this library as a path dependency. It offers interactive tickets,
follow-up evaluations, probability distributions, routing history, and batch
reporting. Run `mix triage` from that directory with `TYPESAFE_API_KEY` configured.
Only the TypeSafe key is needed; see its `README.md` for setup and the local
Keychain invocation.

The pinned development runtime is in `.tool-versions`. `mise install` can install
it. Run commands sharing a build directory sequentially:

```sh
mix deps.get
mix test
mix quality
mix docs --warnings-as-errors
```

`mix quality` runs formatting, compilation with warnings as errors, Credo with
ExSlop, ExDNA, Credence with strict Unicode assumptions, and Dialyzer. All tests
are offline, using local TCP/TLS and HTTP/2 fixtures. Neither Bypass nor Mimic is
needed. CI tests the minimum runtime on Linux and the development runtime on
Linux and macOS. Quality checks run on the development runtime.

An opt-in smoke script makes **one real, billable evaluation** with all three
question types and no retries:

```sh
# macOS Keychain generic password: service typesafe_ai, account api_key
mix run scripts/smoke.exs --keychain

# Or a key provided by the environment
mix run scripts/smoke.exs --env
```

The Keychain command's complete stdout is captured in memory and only its final
newline is removed, so long keys are not truncated. The script prints counts,
never the key. Do not run the retrieval command on its own in a recorded terminal.

See [DESIGN.md](DESIGN.md) for design decisions and the
[upstream API reference](https://docs.typesafe.ai/api), also downloaded in
`docs/api.md`.
