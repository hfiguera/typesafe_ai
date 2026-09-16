# typesafe_ai — TypeSafe Elixir client using Mint

## Idea

Build an Elixir library for TypeSafe's System One API using Mint directly as
the HTTP transport. The library should expose a small, idiomatic interface for
evaluating state with typed questions while managing connections and responses
internally.

This is an initial design proposal; the code examples describe the intended API,
not an existing implementation.

## Naming

The chosen Hex package name is `typesafe_ai`, the OTP application name is
`:typesafe_ai`, and the public module namespace is `TypeSafe`.

The package name identifies the TypeSafe AI service and distinguishes it from a
general type-checking library. The module namespace keeps calls concise and
matches the TypeSafe brand. Naming the library after the service also leaves room
for models beyond Jev. Package and module names do not need to match.

| Module | Responsibility |
| --- | --- |
| `TypeSafe` | Public evaluation API and question helpers. |
| `TypeSafe.Client` | Supervised client and Mint connection ownership. |
| `TypeSafe.Question` | Question representation and validation. |
| `TypeSafe.Response` | Structured answers, model, and token usage. |
| `TypeSafe.Error` | Structured client, transport, and API errors. |

Once version 0.1 is published, callers will add the dependency as:

```elixir
{:typesafe_ai, "~> 0.1"}
```

## TypeSafe's API

TypeSafe evaluates a shared `state` using three question types:

- **Choice:** select from defined options and return their probabilities and confidence.
- **Score:** evaluate descriptive levels and return a probability-weighted score,
  the level probabilities, and confidence.
- **Noul:** return the probability that a yes/no statement is true. There is no
  separate confidence field.

Evaluation uses an HTTPS request with a JSON body:

```http
POST https://api.typesafe.ai/v1/systemone
Authorization: Bearer <API_KEY>
Content-Type: application/json
```

The request contains `state`, `model`, and `questions`. The response contains
`model`, `answers`, and token `usage`. No WebSocket transport is documented.

Independent questions about the same state should share one request. A subsequent
request is needed when its input or questions depend on an earlier answer.
Application code retains control over routing, calculations, and side effects.

## Why Mint

Mint provides direct control over HTTP connections and supports HTTPS, HTTP/1,
and HTTP/2. It represents a connection as a data structure, leaving its process
architecture to the application.

Using Mint directly means the library must implement connection reuse, response
collection, deadlines, reconnection, retry policy, and concurrency limits.
Mint does not provide a connection pool. This adds implementation work, but gives
the library an explicit transport lifecycle that fits Elixir supervision.

Mint's HTTP/2 support does not establish that TypeSafe supports HTTP/2. The client
must work with the protocol negotiated by the server.

## JSON and runtime requirements

Use Elixir's built-in `JSON` module. Require Elixir 1.18 or later and Erlang/OTP
27 or later, using a compatible Elixir/OTP combination.

Native JSON covers the API's maps, lists, strings, numbers, booleans, and `nil`
without adding a JSON dependency. Use `JSON.encode_to_iodata!/1` to prepare
request bodies for Mint and `JSON.decode/1` to decode complete response bodies.

Convert `TypeSafe.Question` structs into explicit request maps before encoding.
Convert decoded response maps into `TypeSafe.Response`, preserving dynamic
question IDs and option names as strings. Normalize encoding failures and
`{:error, reason}` decoding results into `TypeSafe.Error`; invalid input must not
crash the connection owner or interrupt unrelated requests.

Document state inputs as JSON-compatible values. Custom structs need an explicit
conversion to those values or an implementation of `JSON.Encoder`.
`Jason.Encoder` implementations do not apply to native JSON.

The initial version will use native JSON exclusively. Jason and a configurable
JSON backend are unnecessary for the chosen runtime baseline.

## Development and validation environments

Primary development takes place on the macOS laptop with:

- Elixir `1.20.4-otp-29`.
- Erlang/OTP `29.0.6`.

A Linux machine is available through `ssh linux` for platform-specific validation
when needed. Inspect its installed toolchain before choosing validation commands.

The development toolchain is newer than the library's minimum supported runtime.
Keep implementation compatible with Elixir 1.18 and OTP 27, and validate that
minimum combination in addition to the development environment before release.
Passing tests on OTP 29 alone does not establish support for OTP 27.

## Proposed public API

Start a named client under the application's supervisor:

```elixir
children = [
  {TypeSafe.Client,
   name: MyApp.TypeSafe,
   api_key: System.fetch_env!("TYPESAFE_API_KEY"),
   model: "jev-latest"}
]
```

Build questions and submit an evaluation:

```elixir
TypeSafe.system_one(MyApp.TypeSafe,
  state: %{message: "I was charged twice. Please refund me."},
  questions: %{
    "department" =>
      TypeSafe.choice("Which team should handle this?", %{
        "billing" => "Payments, invoices, and refunds",
        "technical" => "Bugs and integration problems",
        "other" => "Anything outside those categories"
      }),
    "urgency" =>
      TypeSafe.score("How urgent is the requested response?", [
        "Can wait until next week",
        "Needs attention this week",
        "Needs attention today"
      ]),
    "refund_requested" =>
      TypeSafe.noul("Does the customer request a refund?")
  }
)
```

Return `{:ok, response}` or `{:error, error}`. A response should expose typed
answers, the model used, and token usage. Preserve question IDs and option names
as strings; never create atoms from server-provided values.

Question helpers should accept structured instructions and criteria where the
TypeSafe API allows them. Validate question shapes locally, while leaving
application-specific decision thresholds to the caller.

## API key handling

Require an explicit, non-empty `api_key:` option when starting `TypeSafe.Client`.
The library does not read environment variables automatically. The application
owns secret retrieval and can use an environment variable, a secret manager, or
different keys for separately named clients.

The supervision example above reads `TYPESAFE_API_KEY` when the application starts.
For releases, the application can instead read the key in `config/runtime.exs`:

```elixir
config :my_app, :typesafe_api_key,
  System.fetch_env!("TYPESAFE_API_KEY")
```

Then pass the configured value when starting the client:

```elixir
{TypeSafe.Client,
 name: MyApp.TypeSafe,
 api_key: Application.fetch_env!(:my_app, :typesafe_api_key)}
```

Keep the key in the client's process state and send it in the
`Authorization: Bearer <API_KEY>` header on each request. Do not embed credentials
in URLs or request bodies. Redact the key and authorization header from logs,
errors, telemetry metadata, and formatted client status output, including through
the GenServer's `format_status/1` callback.

Authentication is configured per client, with no per-request key override in the
initial API. Use separate clients when different credentials are needed. Validate
the option locally and report missing or invalid configuration without including
the supplied secret in the error.

### Local macOS Keychain

The development API key is stored in the laptop's macOS Keychain as a generic
password with service `typesafe_ai` and account `api_key`.

Development tooling may retrieve it with `/usr/bin/security find-generic-password
-s typesafe_ai -a api_key -w`, capturing stdout directly into process memory and
checking the exit status. Remove only the output's terminating newline before
passing the key as `api_key:`. Never print the captured value or include it in
tool output, committed files, or logs.

Keychain access belongs to local development tooling, not the library. Linux
validation should use credential-free tests unless credentials are separately
provided for an explicitly enabled live test.

## Connection architecture

Use a supervised GenServer as the owner of each Mint connection. For the first
version, a named client can own one persistent connection; a pool can be added
when measured throughput requires it.

The connection owner should:

1. Establish HTTPS with certificate verification enabled.
2. Encode and send requests through Mint, retaining the updated connection state.
3. Track pending requests by Mint request reference.
4. Process socket messages through `Mint.HTTP.stream/2` in `handle_info/2`.
5. Accumulate status, headers, and body chunks until each response completes.
6. Decode the JSON response and reply to the waiting caller.
7. Release request state on completion, failure, timeout, or caller termination.

The GenServer must remain responsive while requests are pending. Use deferred
replies with `GenServer.reply/2`, rather than blocking inside `handle_call/3`
while waiting for network data.

Begin with one in-flight request per HTTP/1 connection. If HTTP/2 is negotiated,
support bounded multiplexing while respecting Mint's protocol state and the
server's limits. Bound queued work as well as active requests.

Reuse healthy connections to avoid repeated TLS handshakes. On connection loss,
resolve affected pending requests and reconnect for subsequent work. A failed
connection must not cause requests to be replayed silently.

For separate input states, callers can use `Task.async_stream/3` with bounded
concurrency. Actual transport throughput remains limited by available connections
and negotiated protocol capacity.

## Configuration and errors

Support client defaults and appropriate per-request overrides for:

- API key and base URL configured per client.
- Default model with an optional per-request override.
- Connection timeout and overall request deadline.
- Retry policy and backoff.
- Concurrency and queue limits.

Keep transport failures, timeouts, HTTP API errors, and invalid responses
distinguishable. Retain useful HTTP status and request metadata without exposing
credentials. Avoid logging input state or response bodies by default.

Implement explicit, bounded retries for transient failures, including documented
`429` and `529` responses. Honor a valid `Retry-After` header when present and use
backoff with jitter otherwise. Retries must fit within the overall deadline.

An evaluation is a POST request. If a connection fails after submission, the
server may already have processed and billed the request. Make retry behavior for
these ambiguous failures explicit and configurable; do not assume idempotency.

## Testing approach

Use ExUnit for tests. Do not add Bypass. Mimic is an acceptable test-only
dependency when mocking module calls helps isolate a unit of behavior; add it
only if needed.

Mocks alone do not validate the Mint connection lifecycle. Use small local test
servers built with OTP's `:gen_tcp` and `:ssl` for transport integration tests,
including response chunks, connection reuse, timeouts, disconnects, and TLS
verification. Validate any HTTP/2-specific behavior against an HTTP/2-capable
test server; an HTTP/1 socket fixture does not cover multiplexing.

Keep the default test suite independent of TypeSafe credentials and the live
service. Any live API tests must be explicitly enabled.

## Code quality tools

Use the following tools during development and in CI:

| Tool | Purpose | Integration |
| --- | --- | --- |
| Credo | Consistency, readability, and common mistakes. | `mix credo --strict`. |
| ExSlop (`ex_slop`) | Additional checks for generated-code anti-patterns. | Register `{ExSlop, []}` in Credo's `plugins` list. |
| ExDNA (`ex_dna`) | Structural code duplication detection. | `mix ex_dna`. |
| Credence | Semantic and idiomatic-code analysis. | A project Mix task wrapping `Credence.analyze/2`. |
| Dialyzer | Success typing and typespec analysis. | The `dialyxir` dependency provides `mix dialyzer`. |

Declare these as development/test dependencies with `only: [:dev, :test]` and
`runtime: false`. They must not become runtime requirements for library consumers.
Choose compatible versions during project setup and commit `mix.lock` for
reproducible development checks.

Use ExSlop's recommended checks. If `.credo.exs` declares an explicit
`checks.enabled` list, append `ExSlop.recommended_checks()` in Credo's expected
tuple format; plugin registration alone does not enable them in that case.
Verify the active checks after configuration.

Run ExDNA as a separate check initially, rather than also registering its Credo
integration and reporting the same findings twice. Configure source paths
explicitly and exclude downloaded documentation, dependencies, and build output.

Configure Credence with `assumptions: :strict`, since state and answers may contain
arbitrary Unicode. Its project task should analyze source files without modifying
them, report findings with locations, and exit unsuccessfully on unresolved
findings. Review any automated rewrites and verify behavior with tests.

The validation workflow should include formatting checks, compilation with
warnings treated as errors, ExUnit, Credo with ExSlop, ExDNA, Credence, and
Dialyzer. Run commands sharing a build directory sequentially. Cache Dialyzer's
PLTs by operating system, Elixir/OTP versions, and dependency lockfile.

Address findings before merging. Keep any necessary suppression narrow and
document its reason; do not disable whole tools to make checks pass.

This repository currently contains the design and downloaded documentation.
Install and configure these tools when scaffolding the Mix project.

## Initial scope

- Mint transport and a supervised client connection owner.
- Native `JSON` encoding and decoding; Elixir 1.18+ and Erlang/OTP 27+ required.
- Choice, Score, and Noul question helpers.
- `system_one/2` with structured responses and errors.
- Configurable authentication, model, endpoint, deadlines, and retries.
- Tests against a local server for response assembly, connection reuse,
  timeouts, disconnects, and retry behavior.
- Documentation showing supervision setup and batched questions.
- Credo, ExSlop, ExDNA, Credence, and Dialyzer checks in the development and CI workflow.

Keep pooling and additional convenience APIs for later iterations unless the
initial usage requires them. No WebSocket layer is needed for the documented API.

## References

- [Local TypeSafe API reference](docs/api.md)
- [Question primitives](docs/primitives.md)
- [Confidence semantics](docs/confidence.md)
- [Speculative fan-out](docs/patterns/fan-out.md)
- [Mint HTTP documentation](https://mint.hexdocs.pm/Mint.HTTP.html)
- [Mint architecture guide](https://mint.hexdocs.pm/architecture.html)
- [Elixir JSON documentation](https://elixir.hexdocs.pm/JSON.html)
- [Elixir 1.18 release notes](https://elixir-lang.org/blog/2024/12/19/elixir-v1-18-0-released/)
- [Credo configuration](https://credo.hexdocs.pm/config_file.html)
- [ExSlop setup](https://ex-slop.hexdocs.pm/readme.html)
- [ExDNA setup](https://ex-dna.hexdocs.pm/readme.html)
- [Credence usage and assumptions](https://github.com/Cinderella-Man/credence#usage)
- [Dialyxir setup](https://dialyxir.hexdocs.pm/readme.html)
