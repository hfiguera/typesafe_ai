# Recorded-response tail-latency investigation

This investigates the low-load latency gap in [the recorded-response screen](REPLAY.md).
It keeps unsuccessful tuning ideas and separates timer diagnostics from HTTP
measurements. No live service requests or API keys are used.

**Outcome: no production change or new tuning recommendation.** We found
scheduling stalls outside the library and fixture thermal throttling, but did
not isolate the full cause of ReqLLM's lower tails or demonstrate a reliable
way to beat them. The production client, pool defaults and runtime flags remain
unchanged. Both code candidates are preserved as experiments, not adopted.

Across 157 cases, all **1,705,000 offline HTTP calls** and **150,000 timer-control
calls** completed successfully, with zero driver drops. HTTP accounting includes
10,000 instrumented calls; 2,044 HTTP warmup calls are additional. Completing
every request does not mean every latency criterion passed.

## Longer confirmation

After the exploratory screens, a separate randomized phase compared unchanged
TypeSafe, the small-body candidate described below, and ReqLLM. Each cell has
three 15-second runs. These are median scheduled-arrival p99 values; parentheses
show full-criteria passes. See [all ranges and CPU measurements](TAIL-LATENCY-DATA.md).

| Recorded workload / offered requests per second | TypeSafe | Small-body candidate | ReqLLM |
|---|---:|---:|---:|
| Score, 10 levels / 1000 | 13.12 ms (2/3) | 11.76 ms (2/3) | 11.45 ms (2/3) |
| Score, 10 levels / 4000 | 18.50 ms (1/3) | 21.51 ms (1/3) | 11.60 ms (3/3) |
| Batch, 32 questions / 1000 | 18.68 ms (2/3) | 10.19 ms (3/3) | 9.75 ms (3/3) |

The candidate sends encoded bodies up to 16 KiB through Mint's complete-body
request API, combining headers and the final data frame into one transport write.
For HTTP/2 it first checks both connection credit and the peer's initial stream
window. Larger bodies or insufficient credit retain bounded streaming. It changes
no limits, retry policy or TLS verification.

The batch control's 24,666-byte request **does not use the fast path**, yet its
candidate/baseline timings also differed substantially. This reinforces the
attribution problem. The candidate's median VM CPU per 1000 successes was
111.93 ms versus 120.25 ms for baseline at 4000 req/s, but 209.93 versus 205.00 ms
at 1000 req/s. Those mixed CPU results and the failed latency repetitions do not
justify adopting it for a latency-first goal.

During this confirmation, Linux reached **100°C with 669 new package-throttle
events**. The fixture averaged 135% CPU and peaked at 270% over a two-second
interval, with 100% representing one logical CPU. Mac whole-host CPU averaged
33%, thermal pressure remained nominal, and no network errors/drops increased.
Throttling occurred in multiple variants and workloads, including lower-rate
cases; it is not a measure of how long or how severely the CPU slowed down.
Neither the favorable nor unfavorable differences establish a transport ranking
under these conditions. Earlier short screens also missed criteria without
thermal-throttle increments, so heat does not explain the whole problem.

The next useful step is to isolate slow intervals with scheduler/OS traces on a
quiet client and a fixture with demonstrated thermal headroom. An independently
paced generator would help distinguish offered-arrival timing from client-VM
wakeups. The same recorded inputs, response validation and latency criteria
should remain fixed. More arbitrary pool/window tuning is not supported by
this evidence.

## What the controls established

The Mac can reproduce substantial arrival-scheduling stalls **without TypeSafe,
Mint, TLS or a network**. A control uses the same arrival driver with only
`Process.sleep(5)` per call. With four schedulers and default runtime settings,
its launch-lag p99 was 6.75–551.32 ms across three fresh VMs. Disabling ordinary
scheduler busy-waiting reduced that to 1.61–1.96 ms; one scheduler gave
1.93–2.09 ms. The Linux control's default range was 1.32–1.70 ms.

This demonstrates a host/runtime/driver scheduling contribution. It does not
identify an OTP bug, establish a particular macOS kernel mechanism, or explain
every HTTPS tail. Timer controls have no HTTP warmup and include first-use
effects. Crucially, the successful timer-only flag did **not** consistently
improve HTTPS replay: TypeSafe with `+sbwt none` missed the launch-lag criterion
in all three screening runs. It is not a recommended fix for this library.

Adding 300 microseconds of deliberate CPU work to each timer-control call also
failed to stabilize its tails. Thus the attractive explanation that ReqLLM's
extra CPU work simply keeps the VM awake is not established by this experiment.
No dummy work was added to either client.

## Rejected tuning ideas

All initial HTTPS screens use the same recorded `score_ten` request, 1000 offered
requests/s, five seconds per fresh VM, and three randomized complete blocks.
The table gives TypeSafe's scheduled-arrival p99 range and full-criteria passes.
Compare against the control from the same phase in the complete tables;
different phases are not paired observations.

| Experiment | p99 range, ms | Passes | Finding |
|---|---:|---:|---|
| One connection | 13.40–16.60 | 2/3 | No consistent pass; does not justify changing the pool default |
| Eight connections | 14.11–18.63 | 0/3 | Increasing the pool did not solve launch lag |
| One scheduler | 14.64–14.99 | 3/3 | Stable short screen, but overlapping ReqLLM latency and no scale validation |
| No ordinary scheduler busy-waiting | 17.55–18.90 | 0/3 | Timer-only benefit did not transfer to HTTPS |
| Longer busy-waiting | 16.71–17.48 | 0/3 | No improvement |
| No ordinary/dirty scheduler busy-waiting | 12.87–23.51 | 2/3 | Inconsistent |
| Disable scheduler I/O polling optimization | 15.60–25.38 | 0/3 | Inconsistent |
| Disable scheduler load compaction | 16.79–17.85 | 0/3 | No improvement |
| Disable both busy-waiting and scheduler I/O polling | 16.51–18.11 | 0/3 | No improvement |
| Lower scheduler wakeup threshold | 15.01–23.19 | 0/3 | No improvement |
| Sixteen schedulers | 14.76–21.89 | 0/3 | More schedulers did not solve it |
| macOS per-process latency/throughput tier 0 | 15.07–16.15 | 2/3 | No consistent pass or latency advantage |

These flags affect the whole application VM. The library does not set them.
The [ERTS flag reference](https://www.erlang.org/doc/apps/erts/erl_cmd.html)
describes busy-waiting and I/O polling as runtime tradeoffs. TCP_NODELAY was
already enabled in TypeSafe and Finch. Small payloads at this offered load do
not justify increasing HTTP/2 flow-control windows or admission limits.

An isolated library candidate replaced synchronous deadline/retry timer
cancellation with asynchronous cancellation. The candidate's p99 was
13.62–26.58 ms, versus 13.02–20.23 ms for the unchanged library in the same
randomized phase; it is not retained as a performance fix. Separate
instrumentation measured 10,016 cancellations: p99 0.007 ms, maximum 0.106 ms,
none above 1 ms. Instrumentation perturbs execution, but the result gives no
support for cancellation being the millisecond-scale bottleneck here.
[ERTS documents](https://www.erlang.org/doc/apps/erts/erlang.html#cancel_timer/2)
why asynchronous cancellation can sometimes help; it was an evidence-based
hypothesis, not an assumed improvement.

## Method and evidence

Hardware, versions and wired network are the same as [REPLAY](REPLAY.md):
Mac M4 Max client, Linux i5-1135G7 fixture, Elixir 1.20.4 / OTP 29.0.6,
Mint 1.10.0, Finch 0.23.0, ReqLLM 1.24.0, verified TLS over direct Ethernet.
The persistent Linux fixture retains `+S 4:4`, a fixed 5 ms sleep and the exact
captured bodies. Client flags and connection counts vary only where declared.
HTTP/2 is timed; no SSH request forwarding is used.

Unless a variant specifies otherwise: four client schedulers, four connections,
128 active streams and 1024 queued calls per TypeSafe worker, 1000 ms timeout,
no retries, generator limit 512, and 16 warmup calls outside timing. CPU includes
the client VM and generator. Process CPU additionally includes startup, warmup
and result aggregation. Timer-only controls are separate from all HTTP counts.

Every phase declares its variants and randomized seed before it starts. Later
phases are exploratory follow-ups selected using earlier observations, not a
preregistered study. Each variant receives three repetitions, except the single
instrumented cancellation profile. Original outcomes, drops, scheduled and
call-only latencies, launch lag, per-second buckets and source hashes are kept.
Ranges are repetition minima/maxima, not confidence intervals. A favorable
median alone is insufficient to recommend a change.

All source snapshots are retained for the isolated library candidates. They
are compiled before measurement into separate build directories. Production
candidate timing uses the normal driver and adapters; instrumentation is confined
to the explicitly labeled profile. Host observers run every two seconds, with
clock alignment checked at both ends. Their resolution cannot exclude short
stalls or normal background activity.

Run a declared phase from `bench/` with the verified fixture/resolver setup in
[REPLAY](REPLAY.md#reproduction):

```sh
ERL_INETRC="$PWD/results/tail-investigation/client.inetrc" BENCH_PORT=8455 \
  python3 tail_experiments.py PLAN.json results/new-run
```

Use a fresh output prefix. Plans include exact flags, request counts, workload
and client options. Snapshot/build paths in candidate plans must be adjusted to
the reproducing machine and precompiled before timing. The runner removes
`TYPESAFE_API_KEY` from each child environment. No host-wide power settings change;
the macOS `taskpolicy` control affects only its own benchmark process and children.

The [evidence manifest](recorded/tail-investigation/manifest.json) retains every
case, plan, source snapshot, host observation and checksum. From the repository
root, run `python3 bench/validate_tail.py bench/recorded/tail-investigation` to
check accounting and regenerate the complete tables. Archived source hashes
distinguish baseline, instrumented cancellation, asynchronous cancellation and
small-body candidates. Timer-control and runner revisions are archived too.

Validation: the unchanged benchmark suite passes all 38 tests. The isolated
small-body candidate passes 63 root tests/doctests, including new checks for
the final HTTP/2 data frame and fallback when either stream or connection credit
is insufficient. These establish correctness coverage, not performance benefit.
Documentation builds without warnings. All temporary fixture/monitor processes
were stopped after measurement.
