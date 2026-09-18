# Evidence required for performance claims

TypeSafe aims to add little latency to Jev calls and sustain successful traffic
while keeping tail latency predictable. A benchmark earns a specific statement;
it does not earn a permanent label such as “fastest Elixir client.”

## What a claim must identify

Every numerical comparison must link to the raw results, reproduction command,
library and harness fingerprints, dependency versions, host/runtime, workload,
connection count, offered load, duration, and repetitions. Distinguish API-call
latency from scheduled-arrival latency, and local fixture results from live Jev.
Name what is compared: Finch and Req wrap the same native JSON/typed decoder;
ReqLLM includes different SDK work and response handling.

Use successful req/s. Publish p50/p95/p99 with errors, deadline outcomes, driver
drops/lag, and CPU/memory scope. Show repetition ranges as ranges, not confidence
intervals. Averages across unlike payloads or hosts cannot establish a winner.
Do not hide a slower workload behind an aggregate score.

## Latency-budget claims

Choose the latency/error/driver limits before the run. The current offline screen
uses 20 ms scheduled-arrival p99, zero errors or driver drops, at least 1000
successful samples per repetition, p99 launch lag no greater than 5 ms, and at
least 99% of offered requests completed within the latency budget. The value is
an experimental threshold, not a service guarantee or a recommended product SLO.

A rate qualifies only if every repetition passes. Report the highest point in a
contiguous passing prefix of the tested rates. If the highest point passes, the
upper bound is unknown. If the first point fails, report no qualifying prefix;
do not claim the client has zero capacity. Driver-limited failures do not prove a
client limit. Short screens select longer experiments; they do not prove sustained
production capacity. Tail estimates from tiny live samples do not support rankings.

To claim a latency or throughput advantage, compare the same workload/configuration
on the same host in randomized blocks. Show all repetitions and limitations.
Overlapping ranges or inconsistent repetitions warrant “inconclusive,” rather than
a percentage presented as a general advantage. Repeat under a stronger, independent
load generator when driver lag/drops become material. Investigate lower-rate
failures before treating isolated higher passes as meaningful.

## Current claims ledger

| Statement | Status | Evidence and scope |
|---|---|---|
| The buffered-upload change improved median TypeSafe throughput in the measured macOS batch comparison. | Supported, scoped | [Upload experiment](UPLOADS.md): the recorded 16 KiB state / 32-question local workload, before/after, one and four connections. |
| TypeSafe exceeded Finch's median batch throughput in the recorded post-change local matrices. | Supported, scoped | [Upload experiment](UPLOADS.md); Linux drift prevents an absolute before/after speedup claim. |
| TypeSafe passed the local Linux small-request budget at 1500 offered req/s in three 30-second runs. | Supported, scoped | [Latency report](LATENCY.md): four connections, 256-byte state, one question, synthetic 5 ms delay; p99 7.31–7.38 ms, zero errors/drops. All four adapters passed this case. |
| TypeSafe completed more offered work in the recorded 15-second Linux mixed stress runs. | Supported as an overload observation | [Latency report](LATENCY.md): 6000 offered req/s, four connections; no adapter met all latency/driver criteria across all three repetitions. It is not qualifying capacity. |
| The extended bounded-upload path reduced median client-VM reductions per successful request by about 10.4% in the 6000 req/s mixed comparison. | Supported, scoped | [Investigation](MIXED.md): both versions completed all offered work in three 15-second runs; CPU time ranges overlapped and candidate p99 was slightly higher. Reductions are not elapsed time. |
| The upload candidate has a higher qualifying mixed-load capacity than the committed client. | Not established | [Expanded comparison](MIXED-DATA.md): both qualify only at 6000 req/s in the tested grid; higher-rate repetitions vary and hardware thermal throttling was observed. |
| Current TypeSafe passed the mixed-load budget at 8000 offered req/s with the client on macOS and the fixture on Linux over wired Ethernet. | Supported, scoped | [Mac-client follow-up](MAC-CLIENT.md): three 15-second runs, four connections, 9:1 small/64 KiB requests, p99 8.04–8.45 ms, no errors/drops. Finch, ReqLLM, and previous TypeSafe also passed at this rate; the Linux fixture throttled. |
| Current TypeSafe used less client-VM CPU than Finch at that 8000 req/s point. | Supported, scoped | [Complete follow-up tables](MAC-CLIENT-DATA.md): medians 98.8 versus 114.5 CPU ms per 1000 successful calls, including the driver, with every call successful in each run. This is not a latency or universal capacity lead. |
| TypeSafe development revision `341d824` used approximately 60% less median client-VM CPU per successful request than ReqLLM 1.24.0 at that 8000 req/s point. | Supported, scoped | [Complete follow-up tables](MAC-CLIENT-DATA.md): 98.825 versus 247.65 CPU ms per 1000 successful calls, including the driver. Both passed all three 15-second repetitions with no errors/drops. The SDKs perform different work, and the Linux fixture throttled; this is not a result for Hex TypeSafe 0.1.0 or a universal capacity/latency claim. |
| Removing SSH forwarding yields a higher consistently passing mixed-load rate on the Linux client. | Not established | [Paired network experiment](NETWORK.md): 96 fresh-VM cases, direct and SSH paths over the same wired link. TypeSafe, Finch and Req qualify at 3000 req/s on both paths; ReqLLM has no qualifying point in the tested grid. TypeSafe passes only two of three 6000 req/s runs on each path; Linux thermally throttled. |
| TypeSafe is the fastest or lowest-latency Jev client in general. | Not established | Local results vary by workload and live samples are too small to rank clients. |
| TypeSafe handles a stated req/s against live Jev in production. | Not established | Requires sustained representative external-service tests within account quotas, with reliable tail estimates and independently validated driver capacity. |
| Every release will be faster than Finch, Req, and ReqLLM. | Not a promise | Benchmark each release; competitors and workloads change. |

## Before publishing a release comparison

Run correctness and the offline harness smoke in CI. Run timing comparisons on a
stable, otherwise idle host with the fixture on a separate physical machine when
measuring near saturation. Record temperatures, throttle-counter changes, and
driver lag throughout; a separate BEAM alone does not isolate CPU resources.
Shared CI timings are diagnostic only. Use the **same current harness** for baseline and candidate,
selecting the library checkout with `TYPESAFE_BENCH_PATH`, and alternate their
order across repeated runs. Keep dependency locks and run settings fixed. For
v0.1.0 specifically, the older closed-loop runner's `manual` adapter starts separate
clients; that release does not accept the current `pool_size` option and is not
a drop-in baseline for `curves.exs`.

Check complete reports, sample accounting, fingerprints, outcome counts, and
budget checks. Rerun longer at common passing rates before describing sustained
behavior. A regression in p95/p99, errors, or resource usage needs investigation,
even when peak throughput improves. Retain raw results and commands; update this
ledger and public wording to reflect the measured scope. Avoid automated timing
thresholds on shared runners that would turn host noise into a release decision.
