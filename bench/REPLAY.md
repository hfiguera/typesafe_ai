# Captured-response replay — 2026-09-17

## Results

A [follow-up investigation](TAIL-LATENCY.md) tests the scheduling issue, pool
sizes, runtime settings and library candidates. Its results are separate from
the original screen below.

All **540,000 timed requests succeeded**, with no dropped arrivals. At the common
1000 requests/s offered load, completed throughput was about 997–999 requests/s
including drain time. This does not measure maximum throughput or scalability.

The table shows scheduled-arrival p99 ranges across three runs. Parentheses show
how many runs passed **all** screening criteria, including generator launch lag.
Zero passes means the workload was tested and missed a criterion; it does not
mean requests failed.

| Workload | TypeSafe p99 ms (passes) | Finch | Req | ReqLLM |
|---|---:|---:|---:|---:|
| Synthetic Noul control | 14.76–15.75 (0/3) | 17.87–18.61 (0/3) | 13.65–17.37 (1/3) | 11.86–16.10 (3/3) |
| Small Noul | 16.39–21.90 (0/3) | 18.00–42.73 (0/3) | 14.97–19.78 (1/3) | 11.31–18.85 (2/3) |
| Choice, 3 options | 16.05–24.27 (0/3) | 15.62–21.65 (1/3) | 17.87–18.73 (0/3) | 13.38–17.02 (2/3) |
| Choice, 32 options | 15.76–19.27 (0/3) | 14.57–16.39 (1/3) | 13.63–23.20 (1/3) | 13.09–21.96 (2/3) |
| Score, 3 levels | 17.39–18.71 (0/3) | 13.91–17.07 (2/3) | 16.44–21.99 (0/3) | 10.96–17.11 (3/3) |
| Score, 10 levels | 15.96–18.44 (0/3) | 15.46–17.75 (0/3) | 13.09–17.73 (2/3) | 10.38–13.71 (3/3) |
| Mixed batch, 6 questions | 17.21–23.79 (0/3) | 15.41–21.51 (0/3) | 14.91–18.50 (0/3) | 12.30–15.25 (3/3) |
| Batch, 32 questions | 10.07–10.19 (3/3) | 9.75–10.25 (3/3) | 9.54–9.97 (3/3) | 9.98–10.31 (3/3) |
| Large state | 12.76–15.12 (3/3) | 14.06–44.81 (1/3) | 12.87–40.56 (2/3) | 10.21–11.17 (3/3) |

TypeSafe used less median client-VM CPU per successful request than ReqLLM in
every workload, including the synthetic control. It did not consistently beat
Finch or Req on CPU. ReqLLM often recorded lower tail latency despite its higher
CPU use. The 32-question batch produced close p99 ranges across clients, with
Req's range lowest in this screen. These observations do not establish a
universal latency winner.

Generator launch-lag p99 exceeded 5 ms in **21/27 TypeSafe, 18/27 Finch, 17/27 Req,
and 3/27 ReqLLM runs**. This is why many rows fail even when response p99 is below
20 ms. Timing includes client/driver scheduling effects, so the differences
cannot be attributed solely to HTTP transport or JSON handling. The cause of
this scheduling behavior has not been isolated; a follow-up needs to resolve it
before using these cases to make stronger latency claims.

Host observations found no Linux thermal-throttle increments or network
errors/drops. Linux package temperature ranged from 53–83°C; mean fixture CPU
was 79% of one logical CPU, with a maximum two-second interval of 215%. Peak
observed receive traffic was 574 Mb/s. The Mac's OS thermal state stayed nominal,
with mean whole-host CPU of 35%. These coarse samples cannot rule out short
stalls or interference from background work. Clock-offset estimates changed by
less than 1 ms. Temporary fixture and monitor processes were stopped afterward.

See the [complete latency, throughput, CPU and scheduling tables](REPLAY-DATA.md),
[raw evidence manifest](recorded/recorded-replay/manifest.json), and
[validation](recorded/recorded-replay/validation.json). All 38 benchmark tests
passed on both macOS and Linux. A separate wired smoke check passed all 64
combinations of eight recordings, four clients and two HTTP protocols.

## Corpus

This adds recorded System One payloads to the offline benchmark. Eight synthetic
requests were sent to the real service with `jev-latest`; every successful
response identified `jev-1.13.0`. The [corpus](fixtures/system_one/README.md)
includes Noul, Choice with 3 and 32 options, Score with 3 and 10 levels, mixed
question types, a 32-question batch, and a roughly 68 KB request. Response sizes
range from 119 to 14,261 bytes, including real probability maps and legends.

The goal is to exercise the client with service-generated JSON shapes and sizes.
These synthetic examples are not a production request distribution, an accuracy
dataset, or a sample of every service behavior. One captured response per case
cannot describe inference variability. Existing synthetic stress cases remain
available for controlled size/concurrency experiments and error checks.

## Capture and replay

The capture command is separate from all offline runners and requires `--live`
and an API key. Its eight fixed requests use verified HTTPS/HTTP/2, one attempt
per evaluation, no redirects and no evaluation retries. An unauthenticated HEAD
readiness check establishes the HTTP/2 pool before evaluations begin.

Request and response JSON entity bodies are preserved byte-for-byte. Capture
requests explicitly ask for identity encoding; compressed replies are rejected.
Only content-type/content-encoding response headers are retained. Credentials
and failed response bodies are not stored. Checksums and normal TypeSafe response
validation protect fixture integrity.

The replay server loads recordings once, requires an equal decoded request
(state, questions and model), and returns the exact response bytes. JSON key
order may differ between adapters. Unknown recordings return 404 and mismatched
requests return 409. These paths are tested; a different workload cannot silently
receive a recorded success. Recorded payload sizes describe the captured bodies;
adapters serialize their own semantically equivalent requests.

Eight successful live evaluations reported **29,112 input / 4,276 output tokens**.
The initial fresh-pool capture attempt stopped without recording a response; its
manifest records one client submission attempt. A subsequent unauthenticated
HEAD reproduced Finch's `pool_not_available` startup error. That original
attempt's usage is conservatively unknown; the successful run followed the
readiness fix. Both manifests are retained. There were no further live evaluations
for replay, testing, or timing. Capture durations are individual observations,
not reliable live latency percentiles. Token counts in offline replay results
are repeated captured metadata, not additional consumption.

## Offline timing method

- Mac client: Apple M4 Max, macOS 26.6.2, 16 physical/logical CPUs.
- Linux fixture: Intel i5-1135G7, 4 physical/8 logical CPUs. Both hosts retain
  normal background processes; no power, cooling or governor settings changed.
- Elixir 1.20.4 / OTP 29.0.6, four schedulers per BEAM. Mint 1.10.0,
  Finch 0.23.0, Req 0.7.4, ReqLLM 1.24.0, Bandit 1.12.5.
- Direct wired Ethernet, Mac `10.0.0.2` to Linux `10.0.0.3:8455`, limited by the
  Mac's 1 Gb/s link. Test CA and `localhost` hostname verification stay enabled;
  only the client BEAM resolver maps that name to Linux. No request SSH tunnel.
- Each case starts a fresh client VM. One persistent server loads the recordings.
  Four HTTP/2 connections; TypeSafe allows 128 streams and 1024 queued calls per
  worker, while Finch-backed clients retain their own admission semantics.
- Fixed 5 ms fixture sleep, 1000 ms request timeout, retries disabled, generator
  limit 512 in-flight calls. Warmup is 16 requests per case, outside timing.
- Eight captured cases plus the existing 256-byte, one-question synthetic Noul
  control; all four clients; three randomized complete blocks, seed 20260917.
  Each case offers 1000 requests/s for five seconds: **108 cases / 540,000 offered
  requests**, excluding warmup and the separate smoke.

This is a **common-load screen**, not a capacity curve or sustained-load result.
Only HTTP/2 is timed here. Correctness checks replay all eight cases through all
four clients on both HTTP/1.1 and HTTP/2. The shorter duration and different
payloads mean this screen must not be compared directly with earlier 15-second
mixed-load numbers as an implementation improvement.

The same screening checks apply: every offered request succeeds, no driver
arrivals dropped, at least 1000 successful samples, scheduled-arrival p99 ≤20 ms,
launch-lag p99 ≤5 ms, and ≥99% of offered requests finishing within 20 ms. All
criteria must pass in every repetition. Successful throughput includes drain
time; CPU includes the client VM and generator; memory is an end snapshot.
Medians summarize run statistics. Ranges are min–max, not confidence intervals.

The server returns real response **bodies**, not real inference behavior. Its
5 ms sleep is chosen for comparison and does not use captured response times.
TLS framing, chunking, compression, inference, rate limits, and production traffic
patterns are not reproduced by a JSON recording. The synthetic control builds
its response while recorded cases return preloaded bytes; cross-case differences
include fixture work as well as payload differences. ReqLLM performs different
SDK serialization, model resolution and response-handling work.

Host monitors sample every two seconds. Linux records fixture/host CPU,
temperatures, thermal throttle counters and interface traffic/errors/drops.
Mac records host CPU and OS thermal pressure, not temperature. Approximate
per-case windows include startup, warmup and aggregation; short spikes can fall
between samples. Fixture CPU uses 100% for one logical CPU. Clock offsets were
checked before and after the run.

## Reproduction

With an API key already in `TYPESAFE_API_KEY`, run from `bench/` to make a fresh
capture (at most eight evaluation submissions; failures stop the run):

```sh
ERL_FLAGS='+S 4:4' mix run capture.exs --live --output results/new-captures
```

Existing directories are rejected. Review and retain the resulting manifest and
both body files per case together. Use the same corpus for the server and client.
No key is needed for the following offline commands.

On Linux, from `bench/`:

```sh
ERL_FLAGS='+S 4:4' BENCH_BIND_IP=10.0.0.3 BENCH_PORT=8455 \
  BENCH_RECORDINGS=fixtures/system_one mix run server.exs
```

On the Mac, create `results/recorded-replay/client.inetrc`:

```erlang
{lookup, [file]}.
{host, {10,0,0,3}, ["localhost"]}.
```

Then, from `bench/`:

```sh
ERL_INETRC="$PWD/results/recorded-replay/client.inetrc" BENCH_PORT=8455 \
  ERL_FLAGS='+S 4:4' mix run replay_smoke.exs
ERL_INETRC="$PWD/results/recorded-replay/client.inetrc" BENCH_PORT=8455 \
  BENCH_FIXTURE_DESCRIPTION='Linux recorded-response fixture / Mac client; verified TLS over direct wired Ethernet; fixed 5 ms sleep; no live evaluations' \
  ERL_FLAGS='+S 4:4' python3 recorded_comparison.py \
  --rate 1000 --seconds 5 --repetitions 3 --output results/recorded-replay/main
```

Use a new output prefix for another run. `--recordings PATH` selects another
captured corpus; `--delay 0` removes the artificial sleep, while actual server
CPU/network work remains. `load.exs --recording CASE --recordings-dir PATH`
selects one case for a focused experiment. The default synthetic runners still
work without a corpus. Compile dependencies and run correctness tests before
timing; keep compilers and tests out of measured runs.
