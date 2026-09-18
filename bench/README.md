# Performance benchmarks

This is a separate Mix project. Bandit, Finch, Req, ReqLLM, and their dependencies
are benchmark tools, not dependencies of the published library. By default no
TypeSafe API key is read and no evaluation reaches Jev: the destination is
localhost, using the repository's test CA with TLS verification. The explicit
`curves.exs --live` and `capture.exs --live` commands described below are the only
exceptions.

Use Elixir 1.20.4 / OTP 29.0.6 for reproducing the recorded runs. From this directory:

```sh
mix deps.get --check-locked
mix compile --warnings-as-errors
# Terminal 1: fixture in a separate BEAM. Leave running for all comparisons.
ERL_FLAGS='+S 4:4' mix run server.exs
```

Then in another terminal, also in `bench/`:

```sh
ERL_FLAGS='+S 4:4' mix run run.exs \
  --clients typesafe,finch,req,req_llm --protocols http2 \
  --connections 1,2,4,8 --concurrency 1,32,128 \
  --payloads 256:1,16384:32 --delays 0 \
  --requests 2000 --repetitions 3 --output results/current.json
```

`BENCH_PORT` overrides 8443 in both terminals. Keep the fixture and scheduler count
identical across comparisons. Each process gets four BEAM schedulers here; both
processes still share the machine, including physical cores. Avoid other CPU-heavy
work while measuring. Run clients sequentially, not in simultaneous benchmark VMs.

## Community SDK investigation

[COMMUNITY.md](COMMUNITY.md) records the pinned community SDK adapters, behavior
probes, transport compatibility limits, and controlled timing method. The extra
`jev`, `typesafe_api`, and `typesafe_sdk` dependencies are benchmark-only.
Use `--client jev` or `--client typesafe_api` with `load.exs`; the latter matched
adapter currently requires one HTTP/2 connection. `--profile defaults` selects
connection defaults for TypeSafe, Jev, or TypeSafeAPI, while keeping retries
disabled and the harness timeout. Native TypeSafeSDK uses the
`defaults` profile in a disposable offline VM with the fixture CA loaded into its
BEAM trust cache. It retains its own HTTP/1 transport and is excluded from the
matched HTTP/2 profile.

## Cases and output

- `--clients typesafe,finch,req,req_llm` selects the default four-client comparison.
- `--protocols http1,http2` forces each protocol separately over verified TLS.
- `--connections 1,2,4,8` compares connection counts.
- `--concurrency 1,32,128` sets the maximum number of concurrent caller tasks.
  Task creation and scheduling can leave this bound underfilled; it is not a
  guarantee of that many active requests at every instant.
- `--payloads 256:1,16384:32` means state bytes:number of Noul questions. The
  fixture decodes the full request and generates one valid answer per question.
- `--delays 0,5` injects a server sleep in milliseconds. OS/BEAM timer scheduling
  means a 5 ms sleep does not produce an exact 5 ms response time.
- `--max-concurrency` defaults to 128 streams **per connection** for this harness,
  while the library default is 10. `--max-queue` defaults to 1024 for this harness.
  At 128 callers the one-connection case already has enough stream capacity.
- `--warmup` defaults to 100; the concurrent warmup count is at least twice caller
  concurrency. Every manually routed connection also gets four sequential calls.
- `--requests` and `--repetitions` control measured samples. Scenario order is
  randomized; the output includes each scenario and repetition rather than hiding
  variation behind a single combined percentile.
- `--label` identifies the implementation; `--output` selects the JSON file.

Results include successful requests/second, outcome counts, p50/p95/p99 API-call
latency, first-call timing, VM CPU milliseconds, reductions, garbage collections
and reclaimed words, and VM memory before/after the measured batch. Report median
per-run throughput and percentiles with the individual runs available for review.
Never count fast failures as successful throughput. Latency inside the task
includes request preparation, queueing, TLS I/O, and the selected adapter's response handling; it
excludes waiting for that task to start. Overall batch time includes the driver.

CPU/GC/memory cover the whole client VM, including the load generator. Reclaimed
GC words are not an allocation count, and memory snapshots are not peak memory.
The separate fixture still costs CPU and can limit throughput. First-call timing
starts after client creation and is not a full application-startup metric. Finch
starts HTTP/2 connections asynchronously; first-call timing includes readiness
polling at 10 ms intervals, so use it only as a diagnostic, not a cold-start ranking.

The fixture uses Noul answers and small successful bodies. These runs do not
characterize large Choice distributions, errors, HTTP retries, public internet
latency, service quotas, or actual Jev throughput. There is no “fastest SDK” claim.

## Released baseline and comparison semantics

From the repository root, create an isolated checkout of the release:

```sh
git worktree add --detach /tmp/typesafe-benchmark-v0.1.0 v0.1.0
cd bench
ERL_FLAGS='+S 4:4' TYPESAFE_BENCH_PATH=/tmp/typesafe-benchmark-v0.1.0 \
  mix run run.exs --clients manual,finch --protocols http2 \
  --connections 1,2,4,8 --concurrency 32,128 --delays 0 \
  --payloads 256:1,16384:32 --requests 2000 --repetitions 3 \
  --label v0.1.0 --output results/baseline.json
```

`manual` distributes calls round robin across separately started v0.1.0 clients;
with one connection it is the released client. `typesafe` uses `pool_size` in the
current implementation. Unset `TYPESAFE_BENCH_PATH` to return to the working tree.
Mix recompiles the selected path dependency. Do not change paths in simultaneous
client builds sharing a build directory.

Finch uses the **same** `TypeSafe.Request.prepare/1`, request-body assembly, native
JSON, and `TypeSafe.Response.decode/2`. HTTP/2 is explicitly enabled with
`protocols: [:http2]`; each shard has one multiplexed connection. HTTP/1 uses one
pool with `size` equal to the connection count. Finch already enables TCP_NODELAY;
TypeSafe now enables it too.

This is a comparison of successful request processing, not identical operational
policies. Finch's queues, timeouts, body limits, and cancellation differ, and its
wrapper does not implement TypeSafe retries. TypeSafe disables retries for these
benchmarks. Forced protocols and identical successful response validation prevent
accidentally comparing serialized HTTP/1 with multiplexed HTTP/2 or raw JSON with
typed responses. See [Finch](https://finch.hexdocs.pm/Finch.html) and
[NimblePool](https://nimble-pool.hexdocs.pm/NimblePool.html) for their architectures.

### Req and ReqLLM adapters

The lockfile pins Req 0.7.4 and ReqLLM 1.24.0 (which adds TypeSafe evaluation).
All three Finch-backed adapters start a dedicated, identically configured Finch
instance per scenario. They use the same verified TLS CA, forced HTTP protocol,
connection count, URL, dummy key, state, model, and Noul questions. Redirects and
retries are disabled. Each call uses a 30 s timeout in the closed-loop runner.
Neither application defaults nor a default HTTP/1 pool decide the comparison.

- `req` reuses a `Req.new/1` request template, passes the same native-JSON body
  as `finch`, disables automatic response decoding, and uses the same
  `TypeSafe.Response.decode/2`. This measures Req's request pipeline with the
  existing SDK serialization and validation. It is **not** a benchmark of Req's
  default `json:` / Jason convenience path.
- `req_llm` calls the actual public `ReqLLM.evaluate/4` with a model string and
  `req_http_options: [finch: ...]`. It includes ReqLLM's model resolution, input
  checks, Jason serialization, telemetry steps, and native response normalization.
  A finite `total_timeout` is enabled, including the supervised-task overhead that
  entails in 1.24.0. `max_retries: 0` disables automatic replay. Question maps are
  constructed before timing, just as TypeSafe question structs are for other rows.
  There is no extra TypeSafe decoding layered on top of ReqLLM.

ReqLLM returns boolean probability maps and a generic `ReqLLM.Response`; the other
three return typed `TypeSafe.Response` answers with schema validation. Their
failure handling, queueing, cancellation, and timeout scopes also differ. Thus
ReqLLM is an **end-to-end SDK comparison**, not an isolated transport-overhead
measurement or a claim of equivalent validation. Its additional general-purpose
features are useful work, not necessarily avoidable overhead.

`mix test` checks the wire payload, endpoint, dummy authorization, negotiated
protocol, successful answer values/usage, and single-attempt HTTP failure handling
for each adapter. Smoke runs cover concurrent calls with one and two connections.
ReqLLM's `.env` loading is disabled in benchmark configuration. Keys are explicit
fixture-only values; the benchmark never consults the developer's Keychain.

To reproduce the expanded recorded comparison (rerun all four clients together):

```sh
ERL_FLAGS='+S 4:4' mix run run.exs \
  --clients typesafe,finch,req,req_llm --protocols http2 \
  --connections 1,4 --concurrency 128 --payloads 256:1,16384:32 --delays 0 \
  --requests 5000 --repetitions 5 --label req-comparison \
  --output results/req-comparison.json
```

New outputs include dependency versions, a library source fingerprint, and a
harness fingerprint covering sorted `lib/**/*.ex`, `config/*.exs`, `mix.exs`, and
`mix.lock` (relative path, NUL, file bytes). `lock_sha256` uses the same convention
for `mix.lock` alone. Historical outputs predate the harness fingerprint.

Sources: [Req](https://req.hexdocs.pm/Req.html),
[ReqLLM evaluation](https://github.com/agentjido/req_llm/blob/v1.24.0/lib/req_llm/evaluation.ex), and
[TypeSafe provider source](https://github.com/agentjido/req_llm/blob/v1.24.0/lib/req_llm/providers/typesafe.ex).

For the Linux serial TCP experiment, use `--protocols http1,http2 --connections 1
--concurrency 1 --payloads 256:1 --requests 100 --warmup 10 --repetitions 3`. The
old transport can spend roughly 40 ms per request on this machine, so use the
shorter sample size before launching a large baseline serial matrix.

## Fixed arrival rate and overload

A closed-loop caller starts new work only as previous work finishes. To observe
queueing and rejection under an independently scheduled arrival rate:

```sh
ERL_FLAGS='+S 4:4' mix run load.exs \
  --rate 5000 --requests 10000 --connections 1 \
  --max-concurrency 10 --max-queue 100 --output results/load-1x10.json
ERL_FLAGS='+S 4:4' mix run load.exs \
  --rate 5000 --requests 10000 --connections 1 \
  --max-concurrency 40 --max-queue 100 --output results/load-1x40.json
ERL_FLAGS='+S 4:4' mix run load.exs \
  --rate 5000 --requests 10000 --connections 4 \
  --max-concurrency 10 --max-queue 25 --output results/load-4x10.json
```

The last two configurations have equal aggregate stream and queue limits.
`--delay` defaults to 5 ms, `--timeout` to 1000 ms, and `--max-in-flight` to 512.
`--client finch`, `--client req`, `--client req_llm`, or `--client manual`
selects comparison adapters; the Finch-backed clients do not
use the TypeSafe admission limits. Use TypeSafe to evaluate its bounded queue.

The driver records client outcomes separately from requests it cannot launch
because its own in-flight bound is reached. It also reports maximum scheduling
lag and successful latency measured from both API entry and scheduled arrival.
Throughput includes draining accepted requests. A run with substantial driver
lag or drops is not a clean service-capacity measurement; lower the offered rate
or provision a stronger load generator. Report failures and drops alongside
successful-request percentiles to avoid survivor bias.

Samples default to private ETS storage so retaining observations does not grow
the arrival process's garbage-collected heap. `--sample-storage list` retains a
control mode for diagnosing that effect. Total sample storage still grows with
the number of requests. Measurement stops before sample aggregation. Reports
include per-second buckets keyed by scheduled arrival, including outcomes,
drops, launch lag, and API/scheduled-arrival latency. End-of-drive process and
ETS memory are snapshots, not peaks. `BENCH_FIXTURE_DESCRIPTION` records the
physical topology; set it explicitly when forwarding localhost to another host.

## Mixed-load investigation

[MIXED.md](MIXED.md) separates driver GC, host contention, thermal observations,
and upload scheduling. [MIXED-DATA.md](MIXED-DATA.md) retains every comparison
group; raw reports, commands, and checksums are in its evidence manifest.

`mixed_comparison.py` starts a fresh client VM per case, randomizes complete
blocks, and records commands, source paths, outcomes, and Linux temperatures,
CPU-frequency samples, and thermal-throttle counters when available. Host samples
cover process startup through exit, not exclusively the measured request interval.
It only runs the offline fixture. Do not run tests/compiles on either host while
measuring, and do not compare source versions using different harness revisions.
The recorded main matrix used the archived `main-runner.py` before host sampling
was integrated; a separate monitor captured only its final portion. The current
script and the recorded guards include host samples from every case's start.

Example setup matching the recorded topology, from macOS `bench/` in separate
terminals (the tunnel adds CPU/network overhead and is not direct transport):

```sh
ERL_FLAGS='+S 4:4' BENCH_PORT=8452 mix run server.exs
ssh -N -o ExitOnForwardFailure=yes -R 127.0.0.1:8452:127.0.0.1:8452 linux
```

On Linux, prepare the repository and a clean baseline checkout of `4d9fff4`,
then from the current `bench/` directory:

```sh
BENCH_PORT=8452 ERL_FLAGS='+S 4:4' \
  BENCH_FIXTURE_DESCRIPTION='Mac fixture over SSH reverse forwarding; Linux client on separate physical host' \
  python3 mixed_comparison.py --baseline /tmp/typesafe-mixed-baseline \
  --rates 6000,8000,10000 --seconds 15 --repetitions 3 \
  --output results/root-main-remote
python3 summarize_mixed.py results/root-main-remote.json --output results/mixed-data.md
```

`--clients baseline,typesafe` isolates the library change. `--connections 1`
checks a single multiplexed connection. Workloads are `small`, `batch`, `mixed`
(64 KiB), `medium_mix` (100,000 bytes), and `large_mix` (512 KiB); mixed cases
use nine small calls followed by one larger call. `--storage list` forwards the
driver control option. All other admission/timeout defaults match the report.

For driver diagnostics, set `BENCH_DIAGNOSTICS=results/driver.json` and use
`mix run diagnose.exs` with the same arguments as `load.exs`. Optional
`BENCH_DIAG_CURVES=1` selects `curves.exs`. Sampling and system monitoring change
execution: use these outputs to investigate GC/heap behavior, never rank clients.
`profile.exs` separately records upload function counts or time/allocation profiles.

### Paired direct versus SSH comparison

[Network comparison](NETWORK.md) holds Linux-client/Mac-fixture roles fixed and
alternates direct HTTPS with reverse SSH forwarding over the same wired link.
The `mixed_comparison.py --network-pair DIRECT_INETRC SSH_INETRC` option keeps
matching cases adjacent and reverses each pair's order in the next repetition.
`summarize_network.py` retains separate path tables and reports paired differences.
Use this design to investigate forwarding overhead; swapping machines and
removing forwarding in one step cannot isolate either effect.

### Direct wired fixture

The [Mac-client follow-up](MAC-CLIENT.md) runs the fixture on Linux and the clients
on macOS over Ethernet. To use the recorded addresses, start the fixture on Linux
from `bench/` (replace the address with your Linux machine's wired IP):

```sh
ERL_FLAGS='+S 4:4' BENCH_BIND_IP=10.0.0.3 BENCH_PORT=8453 mix run server.exs
```

The bind address defaults to loopback; binding to a LAN address is explicit.
The fixture accepts synthetic requests using the public test-only certificate.
On the Mac, create an Erlang resolver file containing:

```erlang
{lookup, [file]}.
{host, {10,0,0,3}, ["localhost"]}.
```

Save it as `/tmp/typesafe-lan.inetrc`. `ERL_INETRC` scopes this mapping to the
client BEAM, keeping the TLS hostname `localhost` and full certificate verification.
It does not edit `/etc/hosts` or use SSH forwarding. All four adapters use that
same destination. Prepare the `4d9fff4` baseline checkout, then run from Mac `bench/`:

```sh
ERL_INETRC=/tmp/typesafe-lan.inetrc BENCH_PORT=8453 ERL_FLAGS='+S 4:4' \
  BENCH_FIXTURE_DESCRIPTION='Linux fixture / Mac client over direct wired LAN; localhost resolved to 10.0.0.3 inside client BEAM only' \
  python3 mixed_comparison.py --baseline /tmp/typesafe-mixed-baseline \
  --rates 6000,8000,10000 --seconds 15 --repetitions 3 --output results/mac-lan-main
python3 summarize_mixed.py results/mac-lan-main.json --output results/mac-lan-data.md
```

The separate runtime control restarts the Linux fixture with
`ERL_FLAGS='+S 4:4 +sbwt none +sbwtdcpu none +sbwtdio none'`, then runs the same
Mac command with `--rates 10000 --output results/mac-lan-no-spin`. This disables
idle scheduler polling on the fixture; it does not change the client runtime or
application code. Keep the default and modified fixture results separate.

Host observers run separately and write JSON Lines. On Linux use
`python3 monitor_linux.py --pid FIXTURE_PID --interface enp88s0 --seconds 1800
--output results/server-monitor.jsonl`; replace the PID/interface with the actual
fixture and wired interface. The Linux summarizer assumes the recorded host's
`getconf CLK_TCK` value of 100; adjust it if reproducing on a different system.
On macOS, compile once before timing with `swiftc monitor_mac.swift -o
/tmp/typesafe-monitor-mac`, then run `/tmp/typesafe-monitor-mac 1800 >
results/client-monitor.jsonl`. macOS reports thermal pressure, not temperature.
Do not run compilers or tests on either machine during measurements.

`summarize_hosts.py` joins these observations to a comparison manifest using a
recorded clock-offset check. Host windows are approximate and include startup
and aggregation. `summarize_mixed.py --plot` additionally generates SVG/PNG using
the optional dependencies in `requirements-plots.txt`. Always retain the raw
outcomes and host observations with the plot.

## Captured service responses

The [tail-latency investigation](TAIL-LATENCY.md) tests pool sizes, runtime
settings and isolated library candidates against captured payloads. It includes
timer-only controls and retains unsuccessful experiments.

The [captured-response replay](REPLAY.md) adds eight real System One response
bodies obtained from synthetic inputs: Noul, Choice, Score, mixed batches and
larger payloads. Offline replay requires matching request content and serves the
exact recorded response bytes. All four clients are checked over both HTTP/1.1
and HTTP/2; the recorded timing screen uses HTTP/2.

`capture.exs --live --output NEW_DIRECTORY` is a separate, explicit live command
with at most eight single-attempt evaluations and no evaluation retries. All
replay commands use dummy credentials. See the report for capture accounting,
fixtures, reproduction and the distinction between replayed token metadata and
live usage. The existing synthetic stress cases remain available.

## Latency versus offered load

`curves.exs` runs randomized complete blocks across all four clients. The seed,
settings, source/harness fingerprints, dependency versions, resource diagnostics,
and each repetition are saved. The output is checkpointed after each scenario;
`complete: false` identifies an interrupted run and must not support a claim.

With the separate fixture running, use:

```sh
ERL_FLAGS='+S 4:4' mix run curves.exs \
  --rates 500,2000,8000,16000 --connections 1,4 \
  --workloads small,batch,mixed --seconds 2 --repetitions 3 \
  --seed 20260917 --budget-ms 20 --lag-budget-ms 5 \
  --output results/mac-curves.json
```

For the recorded Linux screen, use `--rates 500,1500,3000,6000`. These are separate
host-specific experiments; do not compare their capacity numbers as a hardware
ranking. Each scenario offers `max(--min-samples, rate * seconds)` requests;
`--min-samples` defaults to 1000. Lowering it is useful for CI correctness smoke,
not p99 claims. `--delay 5`, `--max-concurrency 128`, `--max-queue 1024`,
`--max-in-flight 512`, and `--timeout 1000` are the curve runner's defaults. The
standalone `load.exs` retains its 10-stream / 100-queue defaults.

Workloads are `small` (256 state bytes, one question), `batch` (16 KiB, 32
questions), and `mixed` (nine small calls followed by one 64 KiB, one-question
call). These are periodic synthetic arrivals and payloads, not production traces.
The fixture's 5 ms sleep is chosen to expose queueing; it does not simulate Jev's
response-time distribution. At this rate schedule, the first request is due at
time zero and the last at `(count - 1) / rate`. Throughput includes drain time.

The **chosen local screening budget**, not an application SLO or Jev guarantee,
is 20 ms p99 from scheduled arrival. A rate qualifies only when every repetition:

- Completes every offered request successfully, without driver drops.
- Has at least 1000 successful samples (unless explicitly overridden for smoke).
- Keeps p99 launch lag at or below 5 ms and scheduled-arrival p99 at or below 20 ms.
- Completes at least 99% of all offered requests within 20 ms.

Only a contiguous passing prefix of the tested rates counts. An isolated higher
pass after a lower failure is reported as variation. The highest tested passing
rate is a grid point, not an exact saturation boundary. Passing the top rate
means the test did not establish an upper bound. Driver-limited points cannot
establish client or service capacity. CPU/GC/memory describe the whole client VM;
end snapshots do not measure peak memory. All adapters share the same driver
in-flight cap and connection budget. Admission semantics still differ: TypeSafe
allows 128 active streams per connection plus its queue, while the fixture
advertises 1024 streams to Finch. Saturated results therefore compare complete
configured clients, not identical stream admission policies. Successful-request
percentiles must always be read with errors, drops, and both mixed-workload classes.
The `request_errors` budget reason means not every offered call returned success;
it also appears when the driver dropped work. Use `outcomes` to count actual
client/driver-call failures and `driver_dropped` for calls never launched.

After screening, lengthen runs at a common offered rate for every client. Use
this to confirm passes or investigate inconsistent screen results:

```sh
ERL_FLAGS='+S 4:4' mix run curves.exs \
  --rates 2000 --connections 4 --workloads small \
  --seconds 30 --repetitions 3 --output results/mac-confirmation.json
```

Even 30-second confirmations are not a soak test or proof of production capacity.
Use representative durations, arrival distributions, account quotas, and an
independent load generator before making production scale claims.

The recorded Linux small-request follow-up uses `--rates 1500` with the same
30-second settings. The targeted mixed follow-up uses `--rates 6000
--workloads mixed --seconds 15 --connections 4 --repetitions 3`. All four clients
remain enabled in both follow-ups.

Rebuild tables using the standard Python library; optional static plots require
`matplotlib` and are generated as SVG/PNG next to each input JSON:

```sh
python3 summarize_curves.py recorded/mac-curves.json recorded/linux-curves.json
python3 -m pip install -r requirements-plots.txt
python3 summarize_curves.py --plot recorded/mac-curves.json recorded/linux-curves.json
```

### Bounded live comparison

Run this separately from local benchmarks and other CPU-heavy work:

```sh
TYPESAFE_API_KEY="$(security find-generic-password -s typesafe_ai -a api_key -w)" \
  ERL_FLAGS='+S 4:4' mix run curves.exs --live --output results/mac-live-curves.json
```

It uses the same adapters and the service's fixed HTTPS origin with system trust,
`jev-latest`, one connection, a fixed synthetic invoice question, no retries,
and 1 or 4 offered req/s in seeded randomized blocks. There are two repetitions
per client/rate, eight measured calls plus one warmup each: **at most 144 service
requests**. Warmup failure stops immediately; a measured failure stops after the
current eight-call scenario. Partial reports remain marked incomplete. A failure
may have incurred usage the service did not return. Output contains no credentials,
request/response bodies, or customer data. Model identifiers and successful usage,
including warmup, are retained. The runner accepts only `--seed` and `--output`
in live mode to keep its budget fixed. CI never invokes it.

This tiny live sample checks integration and observed end-to-end timing. Its p99
is effectively a maximum of eight calls, **not a stable tail estimate**. It cannot
rank production capacity, establish an SDK's intrinsic overhead, or demonstrate
routing accuracy. Read the recorded [latency report](LATENCY.md) and
[performance claim rules](CLAIMS.md) before quoting a comparison.

## Upload scheduling experiments

`--large-every 10` on `run.exs` mixes nine small calls (256 bytes, one Noul
question) with one call of the size selected by `--payloads`. The default `0`
keeps homogeneous workloads. Mixed results include separate `workloads.small`
and `workloads.large` outcome counts and latency percentiles, in addition to
total successful throughput. This is a periodic mix, not a production trace.

`load.exs` accepts the same `--large-every` option plus `--bytes` and `--questions`
for the large call (or every call when `--large-every 0`). Its per-workload report
also includes latency from the scheduled arrival. Always inspect driver drops,
scheduling lag, and both classes' errors before comparing latency.

To reproduce the bounded-upload comparison, first create a clean checkout from
the repository root:

```sh
git worktree add --detach /tmp/typesafe-upload-before 4982f5e
```

Start the separate fixture as above, then run from `bench/`:

```sh
TYPESAFE_UPLOAD_BASELINE=/tmp/typesafe-upload-before \
  UPLOAD_OUTPUT_PREFIX=results/mac-upload UPLOAD_RATE=5000 \
  sh upload_comparison.sh
```

Use `UPLOAD_RATE=2000` for the recorded Linux comparison. The script compares
the 16 KiB baseline with the bounded upload fast path using the **same current
benchmark harness**, with TypeSafe and Finch controls. The historical experiment
used the 32 KiB fast path in `4d9fff4`; today's extended path is documented in
[MIXED.md](MIXED.md). Run the script from that historical checkout to reproduce
the old candidate. It separates state size from question count,
checks either side of the old chunk boundary, mixes 512 KiB uploads with small
calls, and runs five repetitions of equal-arrival-rate tests. Uniform matrices
run before/after;
mixed matrices reverse that order; arrival-rate repetitions alternate it.
Scenario order inside each matrix is randomized. The two library versions run
in separate BEAM invocations, never concurrently. Host drift remains a limitation.
Do not run compilation, tests, or other benchmarks concurrently on that host.

## Serialization and smoke checks

```sh
ERL_FLAGS='+S 4:4' mix run phases.exs
mix format --check-formatted
mix test
mix run smoke.exs
mix run summarize.exs recorded/linux-final.json recorded/mac-final.json
```

To profile function call counts (these runs are not timing comparisons):

```sh
ERL_FLAGS='+S 4:4' mix run profile.exs --clients typesafe --protocols http2 \
  --connections 1 --concurrency 128 --payloads 256:1 --delays 0 \
  --requests 2000 --repetitions 1 --output results/profile.json
```

For function time and heap allocation profiles on OTP 29, use `BENCH_PROFILE`:

```sh
BENCH_PROFILE=call_time ERL_FLAGS='+S 4:4' mix run profile.exs \
  --clients typesafe --protocols http2 --connections 1 --concurrency 128 \
  --payloads 16384:32 --delays 0 --requests 2000 --repetitions 1 \
  --output results/profile-time.json
# Repeat with BENCH_PROFILE=call_memory for heap words, or call_count (default).
```

Time/memory profiles use OTP `tprof` on selected TypeSafe, Mint, and Finch modules
in the runner and its spawned processes. Untraced callees contribute to the
nearest traced function; these are not strictly exclusive per-function costs.
The profile covers startup, warmup, and measured requests, including connection
setup. Heap words do not represent peak memory or all off-heap binary allocation.
Profiling changes scheduling: use unprofiled runs for performance comparisons.
See [tprof](https://www.erlang.org/doc/apps/tools/tprof.html).

For the NODELAY-only control, copy the isolated v0.1.0 checkout to a separate
working directory, add `nodelay: true` to `TypeSafe.Config.connect_options/1`'s
transport options, and use that directory as `TYPESAFE_BENCH_PATH` with the serial
command above. Do not modify the released baseline between comparisons.

`phases.exs` measures preparation, final body assembly, and response decoding /
validation without network I/O. Timings include timer overhead and microsecond
resolution; zero means below that resolution, not zero cost.

CI runs the adapter contract tests and checks both protocols, pooling, all four
clients, and the load driver
using an ephemeral local port. Its fixture shares the client VM, so those numbers
are **not** performance results. CI checks correctness, not timing thresholds.

Recorded measurements and conclusions are in [RESULTS.md](RESULTS.md). Raw JSON
for the reported runs is stored in `recorded/`; ad-hoc output in `results/` is ignored.
