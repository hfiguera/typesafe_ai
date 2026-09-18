# Performance and capacity

TypeSafe is designed for latency-sensitive applications using the TypeSafe AI
System One API. This guide covers connection reuse, bounded work, and measurement
at the load your application needs.

The development version adds optional pooling and request-path improvements.
These changes are unreleased; Hex version 0.1.0 uses one connection per client.

## Production hot-path tuning

Use this sequence with representative payloads and traffic in your deployment
environment. There is no single production configuration for every workload.
See [configuration](configuration.md) for option defaults and scope.

1. **Define the target.** Choose the expected arrival rate, p99 latency budget,
   and acceptable error rate. Decide how the application handles overload and
   missed deadlines, such as returning a fallback or deferring work.
2. **Establish a baseline.** Reuse a supervised client with bounded caller
   concurrency. Measure the complete `TypeSafe.system_one/2` call, successful
   requests per second, errors, CPU, and memory. Record cold connections
   separately from steady traffic; [telemetry](telemetry.md) excludes input
   validation/encoding and does not emit events for admission rejection.
3. **Budget deadlines and retries.** Set `timeout` within the application's
   remaining latency budget, leaving room for input encoding, scheduling, and
   downstream work. It is not a hard wall-clock bound on the complete call.
   Set `connect_timeout` for connection establishment. Consider
   `retry: [max_attempts: 1]` when immediate fallback is preferable to retry
   waits; this can reduce recovery from transient failures. Otherwise, keep
   retries within the same request deadline and account for application-level
   retries too. See [errors and retries](errors-and-retries.md).
4. **Tune active work.** For HTTP/2, increase `max_concurrency` gradually while
   checking successful throughput, p99, and errors. Stop when added streams no
   longer help or exceed the budget. Respect the peer's stream limit and service
   quota. This setting does not add concurrency to an HTTP/1 connection.
5. **Test additional connections when justified.** In versions with pooling,
   try `pool_size: 2`, then `4`, if one connection worker is a bottleneck or
   HTTP/1 needs concurrent requests. Repeat measurements at each size; account
   for the increase in total active capacity and queue slots.
6. **Bound waiting.** Tune `max_queue` to absorb only bursts that can finish
   within the deadline. Try a smaller queue, including zero, when early
   `:overloaded` responses are preferable to waiting. Keep upstream task or
   Broadway concurrency bounded even when the client queue is small.
7. **Validate and roll out.** Change one setting at a time. Repeat sustained-load
   and burst tests, including cold connections, timeouts, and overload. Retain
   changes only when they meet both latency and error budgets. Roll out gradually
   while watching the same metrics, with the previous configuration available
   for rollback. Live evaluations consume service quota and may be billed.

### Symptoms and tuning tradeoffs

| Observed symptom | Check or adjustment | Tradeoff or limit |
| --- | --- | --- |
| p99 rises during bursts | Reduce `max_queue` and bound caller concurrency; check whether arrival rate exceeds capacity. | Earlier overload responses replace some waiting; handle them explicitly. |
| `:overloaded` while CPU and service quota have headroom | Check the negotiated protocol and stream limit; try higher `max_concurrency` for HTTP/2. | More in-flight work may increase service latency; a larger queue alone adds no processing capacity. |
| One connection worker limits throughput | Test a larger `pool_size` where supported. | More connections consume resources and multiply per-worker limits. |
| Warm calls are quick but initial calls are slow | Keep clients alive; measure connection setup separately and check `connect_timeout`. | Pool workers connect lazily; a shorter connection timeout can reject otherwise successful cold calls. |
| Retry waits dominate latency, or HTTP 429/529 rises | Inspect attempt counts and delays; reduce offered load and review `retry` against the deadline. | Fewer retries reduce recovery opportunities; more connections do not remove service limits. |
| Large responses increase CPU or memory | Bound caller concurrency, review payload sizes, and set `max_response_bytes` to the application's acceptable limit. | Oversized responses are rejected; adding connections does not remove caller-side decoding work. |

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
