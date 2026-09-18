# Configuration and concurrency

`TypeSafe.Client.start_link/1` is the complete client option reference, including
defaults and accepted values. `TypeSafe.system_one/2` documents per-request
options. Unknown options are rejected.

## Release runtime configuration

Read secrets when your application starts, so building a release does not
require the production key. For an application named `:my_app`, put this in
`config/runtime.exs`:

```elixir
import Config

config :my_app, :typesafe,
  api_key: System.fetch_env!("TYPESAFE_API_KEY"),
  model: "jev-latest",
  timeout: 30_000
```

Then build the child in `MyApp.Application.start/2`:

```elixir
options = Application.fetch_env!(:my_app, :typesafe)

children = [
  {TypeSafe.Client, Keyword.put(options, :name, MyApp.TypeSafe)}
]

Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
```

Supply the environment variable on the machine running the release. The library
does not interpret application environment or fetch secrets; these are choices
made by the consuming application. A changed credential requires restarting the
client with new options.

## Multiple clients

Use separate clients for different keys or endpoint configurations. Both the
registered name and supervisor child ID must be distinct:

```elixir
children = [
  Supervisor.child_spec(
    {TypeSafe.Client,
     name: MyApp.PrimaryTypeSafe,
     api_key: System.fetch_env!("TYPESAFE_API_KEY")},
    id: :primary_typesafe
  ),
  Supervisor.child_spec(
    {TypeSafe.Client,
     name: MyApp.SecondaryTypeSafe,
     api_key: System.fetch_env!("SECONDARY_TYPESAFE_API_KEY")},
    id: :secondary_typesafe
  )
]
```

Start these children under your application's supervisor. Unnamed clients can
instead be addressed by PID. Clients must run on the calling node; remote-node
references return `:unavailable` because deadlines use the local monotonic clock. There is no global default client.

## Bound concurrent work

Each client defaults to one reusable connection. The development version supports
`:pool_size` (unreleased; not available in 0.1.0). HTTP/1 serializes requests per
connection; HTTP/2 multiplexes them up to `:max_concurrency` and the peer's
advertised stream limit per connection. There is no WebSocket transport.

```elixir
{TypeSafe.Client,
 name: MyApp.TypeSafe,
 api_key: System.fetch_env!("TYPESAFE_API_KEY"),
 pool_size: 4,
 max_concurrency: 10,
 max_queue: 25}
```

Use the same `TypeSafe.system_one(MyApp.TypeSafe, ...)` API. A pool size above one
starts a supervisor with independent connection workers. Calls select workers
round robin; a worker that rejects admission is skipped. Once accepted, a request
stays with its worker, including retries. Work is not moved between queues, so
variable request durations can produce uneven queueing. There is no global FIFO
ordering. A crashed worker is restarted independently; its accepted requests
return `:unavailable` and are not silently replayed.

Each connection worker bounds outstanding requests by the current protocol capacity plus
`:max_queue`; requests waiting to retry still consume a slot. Before protocol
negotiation, capacity is conservatively one. If every worker rejects admission, a new
call returns `{:error, %TypeSafe.Error{kind: :overloaded}}` without entering another queue.

With the example above, a warmed HTTP/2 pool admits at most 140 requests
(4 × (10 + 25)), provided each peer allows at least 10 streams. Before negotiation
it admits at most 104 (4 × (1 + 25)). These are bounds on admitted work, not on
the BEAM mailbox or caller allocations. Keep upstream task/Broadway concurrency
bounded too. Increasing the queue increases waiting capacity, not throughput.
See [performance](performance.md) before tuning these limits.

For a list of independent input states, use bounded tasks:

```elixir
questions = %{"refund" => TypeSafe.noul("Is a refund requested?")}
states = ["Please refund the duplicate charge", "How do I update my address?"]

results =
  states
  |> Task.async_stream(
    fn state ->
      TypeSafe.system_one(MyApp.TypeSafe,
        state: state,
        questions: questions,
        timeout: 15_000
      )
    end,
    max_concurrency: 4,
    timeout: 20_000,
    on_timeout: :kill_task
  )
  |> Enum.to_list()
```

Successful task execution wraps the library result: entries are normally
`{:ok, {:ok, response}}` or `{:ok, {:error, error}}`. A task killed by the outer
timeout returns `{:exit, :timeout}`. Results preserve input order here. The outer
task timeout is longer than the client's deadline and also covers local encoding
and scheduling; the default five-second task timeout is often too short.

## Deadlines and cancellation

The request deadline starts after input validation and JSON encoding. It covers
queueing, connection setup, upload, response collection, and retry waits. A
per-request `:timeout` replaces the client's default; `:connect_timeout` bounds
connection establishment separately. Socket sends have a one-second upper
timeout, so a blocked send or scheduling delay can postpone delivery of the
timeout result.

When a caller exits, its pending request is cancelled and its slot is released.
HTTP/1 cancellation closes the connection; HTTP/2 cancellation resets that
stream. Cancellation cannot guarantee that the service has not already evaluated
the request. Subsequent calls reconnect as necessary.

Responses are buffered, with a default limit of 8 MiB per response. A body above
`:max_response_bytes` returns an `:invalid_response` error. There is no public
streaming response API.

## TLS and endpoints

HTTPS verifies certificates and hostnames using OTP's system CA store. To use a
custom CA bundle, pass a PEM path through the client's restricted TLS options:

```elixir
{TypeSafe.Client,
 name: MyApp.TypeSafe,
 api_key: System.fetch_env!("TYPESAFE_API_KEY"),
 transport_opts: [cacertfile: "/etc/my_app/typesafe-ca.pem"]}
```

Only `:cacerts`, `:cacertfile`, and `:versions` are accepted in `:transport_opts`.
The API does not expose an option to disable verification. If you supply a CA
bundle, it replaces the default store for that client.

`:base_url` defaults to `https://api.typesafe.ai`. An optional path prefix is
preserved before `/v1/systemone`. Credentials, queries, and fragments in the URL
are rejected. Plain HTTP is supported for local fixtures or explicitly configured
endpoints. Authentication is always supplied through the client's `:api_key`.
