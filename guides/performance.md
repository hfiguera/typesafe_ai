# Performance and capacity

TypeSafe is designed for latency-sensitive applications using the TypeSafe AI
System One API. This guide covers connection reuse, bounded work, and measurement
at the load your application needs.

The development version adds optional pooling and request-path improvements.
These changes are unreleased; Hex version 0.1.0 uses one connection per client.

## Start with a reusable connection

Keep a supervised client alive between evaluations. A fresh connection requires
DNS resolution, TCP setup, TLS negotiation, and HTTP protocol setup. Pool workers
connect lazily, so the first calls to a larger pool may open more connections.

Batch independent questions about the same state in one evaluation when that
matches the application. Bound concurrent evaluations of separate states.
Avoid slow telemetry handlers: they execute synchronously in the emitting
worker or caller.

## Tune streams before adding connections

HTTP/2 can carry concurrent requests over one connection. `max_concurrency`
defaults to 10 per connection and is capped by the peer's stream limit. A peer's
advertised maximum is a transport limit, not its model throughput or your quota.
Try increasing this setting before assuming a pool is required.

When a single connection owner becomes a CPU bottleneck, try `pool_size: 2` or
`pool_size: 4` and measure again. Each worker owns a Mint connection and processes
its socket events independently. Response decoding and validation run in the
waiting caller, freeing the connection owner to handle other streams. HTTP/1 gains concurrent
requests through additional connections; it has one active request per worker.

```elixir
{TypeSafe.Client,
 name: MyApp.TypeSafe,
 api_key: System.fetch_env!("TYPESAFE_API_KEY"),
 pool_size: 4,
 max_concurrency: 10,
 max_queue: 25}
```

This is a tuning example, not a universal recommended size. More connections can
consume more memory and service resources without improving latency. The default
stays at one. Keep your Broadway processor concurrency or task concurrency within
your measured capacity and service quota.

## Queueing and overload

Capacity and queues are per connection. Requests select workers round robin and
try another worker only when the selected worker rejects admission. Accepted
requests remain on their worker through response handling and retries. Queues
have no global FIFO ordering or work stealing, so mixed request durations can
produce uneven waiting times.

Increasing `max_queue` can absorb a burst, but does not make the service faster.
It can increase tail latency or cause requests to expire before dispatch.
`:overloaded` is explicit admission rejection, not a transport failure. Increasing
pool size does not bypass HTTP 429 responses or the account's service quota.

The admission limit bounds accepted network work. A slot is released before
caller-side response decoding, whose deadline is still checked. It does not bound
caller-side JSON encoding or decoding or the BEAM mailbox when an application launches unbounded callers.
Deadlines, response byte limits, cancellation, validation, and retry policy apply
to every worker. Only explicit admission rejection triggers trying another worker;
an ambiguous transport failure is not silently redistributed.

## Measure what matters

Prioritize p95/p99 latency at the offered load your application needs. Then
maximize successful requests per second while staying within that latency budget.
Peak throughput alone can hide slower individual responses. Track errors,
timeouts, CPU, and memory alongside latency; correctness and bounded work remain
constraints on every optimization. Separate warm requests from startup and connection setup. Measure
both increasing concurrency and a fixed arrival rate: a closed-loop load generator
slows down with the client and can hide overload.

Use [request telemetry](telemetry.md) to track duration, attempts, outcomes, and
successful-attempt token usage. Duration starts after input validation and
encoding, so also time `TypeSafe.system_one/2` from your application when you need
the full call latency. Count returned errors as well: rejected input and admission
overflow do not emit request lifecycle events.

For multi-question evaluations, measure complete workflow latency and useful
answers per second alongside requests per second. Keep the state size, question
count, and answer shape representative of your application. A request with many
questions performs different work from a single-question request.

## Validate your workload

Change one setting at a time and repeat measurements before adopting it. Record
the library and runtime versions, negotiated HTTP protocol, pool size, concurrency,
queue limits, and retry policy. Check load-generator delays and host CPU, memory,
and thermal conditions so they do not obscure the behavior you want to measure.

The repository's [benchmark project](https://github.com/hfiguera/typesafe_ai/tree/main/bench)
contains offline HTTPS fixtures, captured response shapes, load generators, and
engineering reports with reproduction commands. Local fixture timings include
TLS, OS scheduling, client processing, and the fixture server. They do not measure
live model inference or establish production service capacity. Offline runs make
no external API calls and read no credentials.

The [support triage evaluation](examples.md) measures a complete application
workflow against TypeSafe AI, including routing quality, latency, and token usage.
Its small synthetic datasets are useful for regressions. Use representative
labeled data and your deployment environment to validate your own workflow.
