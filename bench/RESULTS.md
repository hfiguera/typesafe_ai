# Performance results — 2026-09-17

The newer [latency-versus-load report](LATENCY.md) compares all four adapters
using matched offered rates and explicit latency budgets. The tables below are
historical closed-loop throughput measurements, not latency-budget capacity claims.

The measurements support optional connection pooling and several request-path
improvements. They do **not** establish the fastest Elixir SDK or predict Jev's
service latency. Finch remains faster in some workloads.

The [expanded Req and ReqLLM comparison](#expanded-comparison-req-and-reqllm)
reruns all four clients together and documents their different API semantics.

A later [bounded upload experiment](UPLOADS.md) profiles the batch gap and
records the retained fast path, payload-boundary checks, mixed traffic, and
paired arrival-rate results. The historical tables below predate that change.

## Method

The original TypeSafe/Finch calls used a local HTTPS Bandit fixture in a separate BEAM process, verified
TLS, native JSON, and complete typed Noul-answer validation. Both processes used
`+S 4:4` and shared the host. The fixture decoded requests and generated responses;
its CPU and OS scheduling are part of these end-to-end timings.

- macOS: Apple M4 Max, Elixir 1.20.4, OTP 29.0.6.
- Linux: Intel i5-1135G7 (4 physical cores / 8 hardware threads), Elixir 1.20.4,
  OTP 29.0.6, kernel 7.1.5. This was a development machine, not an isolated lab host.
- Mint 1.10.0, Finch 0.23.0, Bandit 1.12.5; see `mix.lock` and raw environment data.
- Released baseline: tag `v0.1.0`, commit `93f9fd8cdbd86d7a09ee99e47fd885633869dfde`.
- Final implementation source fingerprint:
  `0863e77b69f9c81f2c4c4663799b041e9deee079a6c86ce8a6f9b29608c36e4e`.
  The [manifest](recorded/manifest.json) defines the fingerprint and hashes the raw files.

The original throughput tables use up to 128 concurrent caller tasks, 128 permitted streams per connection,
2,000 measured calls per repetition, three repetitions in randomized scenario
order, and no artificial server delay. This is deliberately above the library's
default of 10 streams. One connection already has enough stream slots for all
128 callers. Values are medians of individual runs, including p99; they are not
percentiles pooled across repetitions. All reported closed-loop calls succeeded.

See [README.md](README.md) for exact commands, additional concurrency settings,
warmup, cold-start caveats, and the separate fixed-arrival test. The driver creates
a task per call, and scheduling can leave the concurrency bound underfilled.
Per-call latency excludes waiting for the task to start; throughput includes it.

## Linux throughput and latency

“Small” is 256 bytes of state and one Noul question. “Batch” is 16,384 bytes and
32 Noul questions. Baseline rows use one released client. Final rows use the
public `pool_size` API; Finch rows use the same encoding and answer validation.

| Workload | Client | Connections | Successful calls/s | p50 ms | p95 ms | p99 ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Small | v0.1.0 | 1 | 8,079 | 15.607 | 25.846 | 30.125 |
| Small | Final | 1 | 10,814 | 11.851 | 14.077 | 16.189 |
| Small | Final | 2 | 15,328 | 7.916 | 12.607 | 13.860 |
| Small | Final | 4 | 17,320 | 6.678 | 10.704 | 11.706 |
| Small | Final | 8 | 18,020 | 0.867 | 5.295 | 7.438 |
| Small | Finch | 1 | 9,470 | 13.772 | 16.791 | 17.215 |
| Small | Finch | 4 | 15,714 | 6.429 | 14.867 | 18.374 |
| Batch | v0.1.0 | 1 | 4,506 | 27.912 | 34.969 | 43.665 |
| Batch | Final | 1 | 5,874 | 20.713 | 23.192 | 24.016 |
| Batch | Final | 2 | 8,288 | 13.573 | 24.240 | 25.953 |
| Batch | Final | 4 | 9,451 | 10.414 | 27.905 | 35.559 |
| Batch | Final | 8 | 9,146 | 1.742 | 3.629 | 4.745 |
| Batch | Finch | 1 | 6,424 | 19.599 | 23.962 | 25.867 |
| Batch | Finch | 4 | 9,315 | 10.502 | 24.343 | 34.402 |

Sources: [released baseline](recorded/linux-baseline.json),
[final implementation and Finch](recorded/linux-final.json).

Pooling improves throughput, but throughput and tail latency do not move together
in every case. The single-connection final client improves median throughput by
about 34% for Small and 30% for Batch versus the release in these runs. Four final
connections deliver about 2.1× the released single-client throughput in both cases.
Some of that improvement comes from request-path changes, not pooling alone:
the baseline file also includes manually distributed released clients.

Run-to-run variation matters. Final Small at four connections ranged from 15,643
to 19,167 calls/s; Batch ranged from 8,423 to 9,825. Differences of a few percent
against Finch are not convincing evidence of superiority. In particular, Finch
is faster than the final single-connection client for Batch.

## macOS cross-check

Same 128-caller / three-repetition setup, using the final implementation:

| Workload | Client | Connections | Successful calls/s | p99 ms |
| --- | --- | ---: | ---: | ---: |
| Small | Final | 1 | 21,760 | 7.929 |
| Small | Final | 4 | 39,559 | 5.940 |
| Small | Final | 8 | 37,576 | 1.512 |
| Small | Finch | 4 | 37,690 | 7.264 |
| Batch | Final | 1 | 11,619 | 12.019 |
| Batch | Final | 4 | 22,744 | 14.862 |
| Batch | Final | 8 | 22,588 | 2.152 |
| Batch | Finch | 4 | 24,089 | 12.001 |

Source: [macOS raw results](recorded/mac-final.json), which also includes 1 and
32 callers. Four connections nearly double final-client throughput here; eight
record lower successful-request p99 without increasing throughput. Changes in
driver scheduling and effective in-flight concurrency can affect those tails;
this does not establish lower latency at a matched arrival rate. Finch wins
the four-connection Batch throughput comparison. The default remains one
connection; the right pool size depends on workload and the metric being tuned.

## Expanded comparison: Req and ReqLLM

A second matrix adds Req 0.7.4 and ReqLLM 1.24.0. All four clients were rerun
in randomized scenario order on each host: **5,000 measured calls × five
repetitions**, HTTP/2, up to 128 concurrent callers, one/four connections, both
payload sizes, and no artificial server delay. Each host completed 400,000
measured calls with zero failures. Hardware, Elixir/OTP, scheduler counts, and
the separate verified-TLS fixture setup match the earlier measurements.

The library source is unchanged. These are new runs with an expanded benchmark
application; compare clients within this matrix rather than interpreting changes
from the earlier tables as regressions or improvements. Both VMs share host CPU,
and the Linux machine showed substantial run-to-run variation. Ranges below are
minimum/maximum throughput across five repetitions, **not confidence intervals**.
Reported p99 values are medians of the five per-run p99 values.

Req reuses a prepared request template with our native JSON encoding and typed
answer validation. ReqLLM uses its public `evaluate/4` API, model string resolution,
Jason encoding/decoding, and its own response normalization. Its finite total
timeout includes the library's supervised request task. It returns a generic
response with boolean probability maps; no TypeSafe validation is added on top.
All Finch-backed adapters use the same dedicated pool settings, verified TLS,
dummy key, wire payload, and disabled retries/redirects. These SDK paths do
**different work**, so the results do not isolate the cost of ReqLLM's transport.
See [adapter semantics and reproduction commands](README.md#req-and-reqllm-adapters).

### Linux

| Workload | Client | Connections | Median calls/s | Run range calls/s | Median p99 ms |
| --- | --- | ---: | ---: | ---: | ---: |
| Small | TypeSafe | 1 | 9,748 | 8,418–9,924 | 17.864 |
| Small | Finch | 1 | 7,730 | 6,439–9,481 | 22.116 |
| Small | Req | 1 | 7,913 | 7,245–9,718 | 21.323 |
| Small | ReqLLM | 1 | 5,601 | 4,700–6,144 | 28.514 |
| Small | TypeSafe | 4 | 13,153 | 12,382–18,802 | 16.152 |
| Small | Finch | 4 | 10,990 | 10,508–13,878 | 26.477 |
| Small | Req | 4 | 13,809 | 10,211–14,543 | 25.275 |
| Small | ReqLLM | 4 | 5,113 | 2,711–5,839 | 27.456 |
| Batch | TypeSafe | 1 | 4,856 | 4,600–5,519 | 29.469 |
| Batch | Finch | 1 | 5,104 | 4,841–6,189 | 31.583 |
| Batch | Req | 1 | 4,967 | 4,345–6,313 | 33.314 |
| Batch | ReqLLM | 1 | 2,594 | 2,410–3,213 | 58.739 |
| Batch | TypeSafe | 4 | 6,623 | 6,386–7,936 | 45.578 |
| Batch | Finch | 4 | 7,591 | 6,646–9,389 | 41.821 |
| Batch | Req | 4 | 6,602 | 6,129–8,344 | 47.421 |
| Batch | ReqLLM | 4 | 2,537 | 2,324–3,544 | 111.235 |

Source: [Linux raw comparison](recorded/linux-req-comparison.json).

### macOS

| Workload | Client | Connections | Median calls/s | Run range calls/s | Median p99 ms |
| --- | --- | ---: | ---: | ---: | ---: |
| Small | TypeSafe | 1 | 21,749 | 21,576–22,040 | 7.826 |
| Small | Finch | 1 | 19,846 | 19,090–20,167 | 8.893 |
| Small | Req | 1 | 20,337 | 19,278–20,430 | 8.819 |
| Small | ReqLLM | 1 | 14,473 | 13,801–14,881 | 10.622 |
| Small | TypeSafe | 4 | 40,941 | 40,924–42,217 | 5.670 |
| Small | Finch | 4 | 38,032 | 37,624–38,283 | 7.858 |
| Small | Req | 4 | 38,058 | 37,520–38,428 | 8.935 |
| Small | ReqLLM | 4 | 17,467 | 17,089–18,267 | 7.512 |
| Batch | TypeSafe | 1 | 11,255 | 10,923–11,868 | 13.214 |
| Batch | Finch | 1 | 13,139 | 13,007–13,535 | 12.457 |
| Batch | Req | 1 | 13,265 | 12,212–13,520 | 13.399 |
| Batch | ReqLLM | 1 | 7,339 | 7,033–7,515 | 19.777 |
| Batch | TypeSafe | 4 | 23,012 | 21,994–23,071 | 13.201 |
| Batch | Finch | 4 | 23,806 | 23,689–24,097 | 13.092 |
| Batch | Req | 4 | 23,585 | 23,463–24,063 | 14.003 |
| Batch | ReqLLM | 4 | 8,244 | 8,023–8,311 | 33.334 |

Source: [macOS raw comparison](recorded/mac-req-comparison.json).

TypeSafe's median throughput exceeds this ReqLLM configuration in every tested
case. With four connections the ratio is about 2.6× on Linux and 2.3–2.8× on macOS.
This is a local successful-call throughput result, not an equivalent reduction
in production Jev latency. ReqLLM provides a broader provider abstraction and its
validation, normalization, and deadline machinery differ from TypeSafe's.

Req and Finch remain competitive. Req records the highest Linux four-connection
Small median, Finch the highest Linux four-connection Batch median, and their
ranges overlap TypeSafe's. On macOS, TypeSafe leads Small while Finch/Req lead
Batch. Small differences, especially on the variable Linux host, are not a
reliable general ranking. More connections do not help ReqLLM in every case;
these results do not by themselves identify its bottleneck.

The 16 adapter contract tests verify payloads, protocol negotiation, expected
answers/usage, and one-attempt HTTP 503 handling. CI also runs concurrent and
fixed-arrival smoke checks for all four clients. The public library gains no
Req or ReqLLM dependency from this comparison.

## TCP_NODELAY control experiment

Linux serial calls exposed a roughly 42 ms delay with v0.1.0. To isolate the cause,
an otherwise unchanged copy of the release was tested with **only**
`nodelay: true` added to Mint's transport options. Each row below uses one caller,
one connection, Small payloads, 100 measured requests and three repetitions.
Values are median per-run p50 API-call latency in milliseconds.

| Protocol | Released | Release + TCP_NODELAY only | Final |
| --- | ---: | ---: | ---: |
| HTTP/1.1 | 41.891 | 0.109 | 0.110 |
| HTTP/2 | 41.916 | 0.158 | 0.165 |

Sources: [released serial](recorded/linux-serial-baseline.json),
[NODELAY-only control](recorded/linux-nodelay-only.json),
[final serial](recorded/linux-serial-final.json).

This isolates TCP buffering as the dominant cause in this fixture. It does not
mean real Jev evaluations will take 0.1 ms or improve by the same amount. Actual
service time and network conditions remain external to the SDK. Tests verify
that both TCP and TLS client sockets have TCP_NODELAY enabled.

## Fixed arrival rate

A separate HTTP/2 run offered 10,000 Small requests at 5,000 requests/s with a
nominal 5 ms fixture sleep, a 1 s deadline, and a 512-request driver bound. These
are single diagnostic runs, not repeated estimates of maximum capacity. The p99
column includes time from the scheduled arrival, including driver scheduling.

| Connections × streams | Queue per connection | Successes | Overloaded | Driver drops | Successful p99 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 × 10 | 100 | 3,433 | 6,567 | 0 | 66.970 |
| 1 × 40 | 100 | 10,000 | 0 | 0 | 7.309 |
| 4 × 10 | 25 | 10,000 | 0 | 0 | 7.085 |

Sources: [1 × 10](recorded/linux-load-1x10.json),
[1 × 40](recorded/linux-load-1x40.json),
[4 × 10](recorded/linux-load-4x10.json).

The last two rows have equal aggregate stream and queue limits. Increasing the
stream limit alone was sufficient for this workload. The default's high successful
p99 reflects queueing; it excludes the many rejected calls, which must be reported
alongside it. Maximum driver scheduling lag was 2.034, 1.971, and 3.294 ms,
respectively. No driver drops occurred. These figures support measuring before
adding connections rather than assuming every busy pipeline needs a pool.

## Implementation choices and remaining limits

The branch adds an opt-in supervised pool, enables TCP_NODELAY, tracks only
unfinished uploads, skips queue scans on normal completion, and moves body
assembly plus response decoding/validation into callers. Encoded request bodies
are reused across retries; schemas stay in callers and complete request bodies
cross process boundaries as binaries. Call-count profiling identified repeated upload
checks for requests whose uploads had already finished; `profile.exs` can reproduce
that investigation. Profiling output is not used for throughput rankings.

No response validation, byte limit, deadline, cancellation, or retry rule was
removed to improve a benchmark. Network admission slots are released before
caller-side decoding, so applications must also bound caller concurrency.
Queues remain per connection and are not globally FIFO; variable request durations
can cause uneven queueing. A worker restart can briefly make routing unavailable.

Finch remains a useful comparison and wins some cases. The harness shares hardware
with its fixture, uses only successful Noul responses, has short repetitions, and
records VM-wide CPU/GC/memory snapshots rather than isolated SDK CPU or peak memory.
The raw files preserve those diagnostics; they should not be read as allocation
profiles. Large Choice distributions, long steady-state runs, production network
conditions, and real workload traces remain useful future profiling targets.
