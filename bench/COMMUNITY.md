# Community TypeSafe SDK investigation

This is an internal engineering comparison, not release positioning. Production
library code is unchanged. The packages are independent projects with different
APIs and operational policies; successful-request timings are not a feature ranking.

## Versions and scope

The benchmark lockfile pins `jev` 0.1.0, `typesafe_api` 0.1.0-alpha.3,
`typesafe_sdk` 0.3.0, Pristine 0.4.0, ExecutionPlane HTTP 0.2.0, Req 0.7.4,
and Finch 0.23.0. Our implementation is the development branch after `a99077f`,
including unreleased pooling; it is not the Hex 0.1.0 package. Adding Pristine
required resolving JSV to 0.21.2 (previously 0.22.0); this is within ReqLLM's
supported range. Historical measurements keep their historical lockfiles.
All additional dependencies belong to `bench/`, not the published library.

| Package | Public evaluation path | Work included |
|---|---|---|
| TypeSafe development | `TypeSafe.system_one/2` | Input validation, native JSON, Mint transport, request-relative typed validation |
| `jev` 0.1.0 | `Jev.HTTP.post/3` | Question normalization, native JSON, Req transport, reply-map conversion, per-answer telemetry |
| `typesafe_api` 0.1.0-alpha.3 | `TypeSafeAPI.evaluate/4` | Question preparation, native JSON, Req transport, typed validation and enriched answers |
| `typesafe_sdk` 0.3.0 | `TypeSafeSDK.evaluate/4` | Strict semantic evaluation through its generated operation and Pristine runtime; native HTTP/1 in the defaults follow-up |

Question objects are constructed before timing for all clients. We use ordinary
public evaluation calls, not the prepared-question APIs offered by `typesafe_api`
and `typesafe_sdk`. Jev's GenServer workflow wrapper is not timed. No extra
TypeSafe decoder is placed after another SDK's response handling.

Sources are the pinned Hex package contents: [jev](https://hex.pm/packages/jev/0.1.0),
[typesafe_api](https://hex.pm/packages/typesafe_api/0.1.0-alpha.3),
[typesafe_sdk](https://hex.pm/packages/typesafe_sdk/0.3.0), and
[Pristine](https://hex.pm/packages/pristine/0.4.0). The lockfile retains package checksums.

## Compatibility findings

- `jev` and `typesafe_api` successfully replay all eight captured service response
  shapes. Tests verify payloads, model, usage, answer values, distributions,
  authorization, paths, and HTTP/2 negotiation. Jev emits optional `criteria: null`;
  replay treats that as equivalent to an omitted criteria field. All other request
  content must still match the capture. Recorded request-byte counts describe
  the corpus; actual wire size and JSON member order can vary by SDK.
- Jev's public question IDs and Choice labels are atoms. The benchmark converts
  the finite, trusted fixture IDs/labels before timing. It never interns names
  received from the server. `typesafe_api` receives an ordered list of question
  pairs, as its API requires; JSON member order can differ between SDKs.
- With Req 0.7.4, `typesafe_api`'s atom-only named-pool option triggers repeated
  deprecation warnings. Its documented `req_options: [connect_options: ...]`
  path avoids this. The matched adapter therefore uses one dynamically managed
  HTTP/2 connection. No dependency code is patched and warnings are not suppressed.
  The adapter rejects other matched connection/protocol combinations explicitly.
- Despite its name, `Pristine.Adapters.Transport.Finch` in 0.4.0 delegates unary
  calls to ExecutionPlane's OTP `:httpc` transport. It does not forward the context's
  TLS CA options. The native SDK succeeds against a plain loopback HTTP/1 fixture,
  but fails the private-CA HTTPS fixture with `unknown_ca`. We did not disable TLS
  verification, install a system CA, or substitute a custom transport. A separate
  disposable BEAM then loaded the fixture CA with `:public_key.cacerts_load/1`.
  All eight captures passed over verified HTTPS/1 using the unmodified SDK.
  This VM-local trust setup enables the defaults follow-up. It has no row in the
  matched HTTP/2 screen; that means **not measured there**, not slow.
  [Native TLS probe](recorded/community/native-sdk-probe.json) retains the results.

## Behavior observations

[Raw observations](recorded/community/behavior.json) contain 28 synthetic local
probes, seven per client. Retries were disabled; every probe produced one fixture
request. These probe durations include startup and are not performance rankings.
`typesafe_sdk` uses plain loopback HTTP/1 here; the other three use verified HTTPS/2.

| Probe | TypeSafe | Jev | TypeSafeAPI | TypeSafeSDK |
|---|---|---|---|---|
| Successful Noul | Success | Success | Success | Success |
| HTTP 429 / 529 | HTTP errors | HTTP errors | Rate-limit / overload errors | Rate-limit / server errors |
| Missing requested answer | Error tuple | Success with missing answer | Error tuple | Error tuple |
| Noul probability `2.0` | Error tuple | Success with invalid value | Error tuple | Error tuple |
| Malformed JSON | Error tuple | Raises `JSON.DecodeError` | Error tuple | Error tuple |
| 200 ms response with 100 ms timeout | Error tuple | Error tuple | Error tuple | Error tuple |

These cases establish behavior for these inputs and versions, not comprehensive
correctness. A receive timeout is not equivalent to an end-to-end deadline.
The probes do not test disconnect ambiguity, cancellation cleanup, queue
saturation, automatic retry schedules, or reconnect behavior. Our existing
library tests cover our own policies; they are not evidence about another SDK.

Source review adds useful context: `typesafe_api` separates per-attempt response
timeouts from a retry-start budget and offers a bounded `evaluate_many` helper.
`typesafe_sdk` offers bounded batches and cancellation tokens. Jev's GenServer
wrapper dispatches supervised tasks and routes replies into callbacks. Those
higher-level workflows are outside this single-evaluation timing screen.

## Timing method

Linux is the client (Intel i5-1135G7); the Mac is the fixture (Apple M4 Max), over
direct 1 Gb Ethernet, with no SSH forwarding. Both run Elixir 1.20.4 / OTP 29.0.6.
The controlled client and fixture both use four schedulers with ordinary and
dirty scheduler busy-waiting disabled. These are experiment settings, not library
recommendations. The fixture replays exact captured response bytes after a 5 ms
sleep; there is no inference and no new token usage. Every request carries a
dummy credential.

Three initial five-second Linux timer-only controls, using normal runtime
settings, passed our 5 ms launch-lag limit (p99 1.44–2.00 ms). The initial HTTP
screen used those settings at 500 and 2000 requests/s, but Linux subsequently
thermally throttled. It was stopped after 31 completed cases; its incomplete
manifest and outputs are retained as diagnostics, not a completed ranking.
Two default-TypeSafe cases at 2000 requests/s returned 2978 and 3032 `:overloaded`
errors out of 10,000 offered calls each. Ten active streams cannot sustain that
arrival rate with this fixture's observed response times. These observations
reinforce the need to size concurrency for the workload; they do not establish a
hardware-independent capacity ceiling.

The controlled follow-up lowers the rate to 500 requests/s, uses ten-second
cases, and waits for three consecutive temperature readings at or below 70°C
before each case. It samples Linux temperatures and thermal-throttle counters
throughout each fresh VM's lifetime and stops if any throttle counter increases.
The reduced rate, cooling, and runtime settings changed together: this follow-up
does not isolate which intervention helped. Every HTTP run must also pass its
own launch-lag and outcome checks.

Two profiles remain separate:

- **Matched:** one verified HTTP/2 connection per client, no retries, 1000 ms
  request timeout. TypeSafe allows 128 active streams and 1024 queue entries;
  Finch-backed clients use their native admission policies and the fixture's
  1024-stream maximum. Equal connection counts do not imply equal admission rules.
- **Default connection settings:** TypeSafe retains its one connection, ten-stream
  limit, and 100-entry queue; Jev and TypeSafeAPI retain Req's default connection
  settings. Fixture checks observe HTTP/2 for TypeSafe and HTTP/1.1 for the two Req
  clients. The later native TypeSafeSDK path also uses HTTP/1.1. Pooling/protocol
  defaults are therefore intentionally different.
  Retries are still disabled and the timeout remains 1000 ms: these are connection
  defaults, not every SDK's complete defaults.

The matched follow-up uses `noul_small`, `score_ten`, and `batch_32`; the defaults
follow-up uses `noul_small`. Each has 100 sequential warmup calls. Three seeded
randomized complete blocks run each case in a fresh client VM. All use a 512-call
driver in-flight cap and the same fixture. Compilation and tests finish before
measurement. CPU/GC/memory include the client VM and driver. Memory snapshots are
not peaks. This limited offered rate cannot rank maximum throughput or scalability.

The first controlled phase completed all 36 cases: 180,000 measured calls plus
3600 warmups, zero request errors/drops, all latency criteria passed, and no new
Linux thermal-throttle events during any case. Peak sampled client temperature
was 94°C, so this is still a mobile host with limited thermal headroom.

At 500 offered requests/s, the matched HTTP/2 median scheduled-arrival p99 values
were:

| Captured shape | TypeSafe | Jev | TypeSafeAPI |
|---|---:|---:|---:|
| Small Noul | 10.01 ms | 9.93 ms | 9.68 ms |
| Ten-level Score | 9.68 ms | 10.54 ms | 10.20 ms |
| 32-question batch | 12.48 ms | 12.38 ms | 14.65 ms |

Several latency ranges overlap; there is no universal latency winner. TypeSafe used
the lowest median client-VM CPU per success in each group, including the separate
connection-default groups. The batch CPU difference versus Jev was modest
(1057.6 versus 1098.0 ms per 1000 successes), and the SDKs perform different
validation/enrichment work. All clients sustained the offered 500 requests/s;
these measurements do not determine their maximum throughput.
[Complete first-phase tables](COMMUNITY-DATA.md) retain every repetition.

A separate defaults follow-up adds the native TypeSafeSDK HTTPS/1 path and reruns
all four SDKs in randomized blocks at the same 500 requests/s. It uses the same
cooling/thermal checks. Its harness adds the native adapter and validates profile
selection; phases retain separate fingerprints and tables. The initial harness
is archived in `recorded/community/harness-first/` for exact reproduction; the
second is in `harness-defaults/`. Restore the desired archive's `lib/`, `config/`,
`mix.exs`, and `mix.lock` into `bench/` in an isolated checkout to reproduce that
phase's harness fingerprint.

The defaults follow-up completed another 12 cases: 60,000 measured calls and
1200 warmups, all successful and within the screening criteria, with no new
thermal-throttle events. Its median results are:

| Client connection defaults, small Noul at 500 req/s | p99 | CPU ms / 1000 successes |
|---|---:|---:|
| TypeSafe (HTTP/2) | 8.50 ms | 411.8 |
| Jev (HTTP/1.1) | 8.91 ms | 800.6 |
| TypeSafeAPI (HTTP/1.1) | 9.40 ms | 828.4 |
| TypeSafeSDK (HTTP/1.1) | 9.37 ms | 1166.2 |

All sustained about 499.7 successful requests/s including drain time. TypeSafe's
median CPU and p99 were lowest in this defaults phase, but overlapping latency
ranges and different connection defaults prevent an intrinsic transport ranking.
[Every defaults repetition](COMMUNITY-DEFAULTS-DATA.md) is retained. Across both
completed phases, 240,000 measured calls and 4800 warmups succeeded.
[Host observations](recorded/community/host-summary.json) show nominal Mac thermal
pressure and zero Linux package-throttle/network error/drop increments during
both controlled phases. [The evidence manifest](recorded/community/manifest.json)
indexes checksums, source snapshots, plans, and raw outputs. All 53 benchmark
tests pass on both macOS and Linux. No live API
calls were made. The interrupted hotter screen remains visibly incomplete.

## Reproduction

Run from `bench/`. No real API key is needed. Start the fixture on the Mac:

```sh
mix deps.get --check-locked
mix compile --warnings-as-errors
BENCH_BIND_IP=10.0.0.2 BENCH_PORT=8467 BENCH_RECORDINGS=fixtures/system_one \
  ERL_FLAGS='+S 4:4 +sbwt none +sbwtdcpu none +sbwtdio none' mix run server.exs
```

On Linux, use a copy of the same checkout and lockfile, compile first, and set
`ERL_INETRC` to an Erlang hosts file mapping `localhost` to the fixture address.
TLS still verifies the certificate for `localhost`. Adapt the interface and
addresses for your own network; retain evidence of the actual route and link.

```sh
python3 tail_experiments.py recorded/community/timer-plan.json results/community-timer
BENCH_PORT=8467 ERL_INETRC="$PWD/recorded/community/linux.inetrc" \
  BENCH_FIXTURE_DESCRIPTION='Linux client to Mac fixture over direct 1 Gb Ethernet; verified TLS; recorded bodies; 5 ms fixture delay' \
  python3 community_screen.py recorded/community/controlled-plan.json results/community-controlled
# With the same environment, the four-SDK connection-default follow-up:
BENCH_PORT=8467 ERL_INETRC="$PWD/recorded/community/linux.inetrc" \
  python3 community_screen.py recorded/community/native-plan.json results/community-defaults
```

Run host monitors on both machines during measurement. Do not classify thermally
throttled or driver-limited runs as capacity evidence. Keep the full raw output,
including failures. Generate the tables after collecting the output into one directory:

```sh
python3 summarize_community.py recorded/community --output COMMUNITY-DATA.md
python3 summarize_community.py recorded/community --manifest community-defaults.json \
  --output COMMUNITY-DEFAULTS-DATA.md
mix test
mix run community_probe.exs --output results/community-behavior.json
mix run native_sdk_probe.exs --output results/community-native-tls.json
python3 validate_community.py recorded/community
```

## Engineering opportunities

Prepared question sets are worth a separate experiment: both TypeSafeAPI and
TypeSafeSDK expose them, which could avoid repeating validation/encoding for a
fixed schema across many states. This screen does not quantify that benefit.
Rich answer helpers (ranked choices, margins, expected versus modal scores) and
application-level fixtures are also useful usability ideas independent of HTTP
speed. We have not changed production code or adopted these APIs in this task.
