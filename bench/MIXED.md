# Mixed-load investigation — 2026-09-17

Follow-up: [Mac client with a Linux fixture over wired Ethernet](MAC-CLIENT.md)
reverses the machines, records both hosts throughout, and tests a separate fixture
runtime setting. It leaves the library and these historical results unchanged.

The earlier mixed-load result combined client work, load-generator pauses, and
an unstable host. It did not isolate an SDK's maximum capacity. We found concrete
contributors and reduced TypeSafe's upload work, but cannot assign every historical
outlier to one cause or claim that a library change eliminates host saturation.

## What caused the variation?

**The arrival driver accumulated every result on its own heap.** In fresh-VM
diagnostic runs of the original harness, its sampled memory reached about 22.6 MB
after 90,000 calls. System monitoring recorded driver GC pauses of 6–9 ms during
measurement; aggregation after measurement caused additional pauses. This matters
with a 5 ms launch-lag budget. It does not, by itself, explain 500 ms response tails.
The new default stores samples in a private ETS table, outside the issuing
process's garbage-collected heap. Total sample storage still grows with request
count. The clock and VM resource measurement stop before aggregation, and
per-second buckets retain latency, lag, outcomes, and dropped arrivals.

A same-harness list/ETS diagnostic control used the committed library, 3,000
offered req/s for 30 seconds, and 90,000 calls in each run. Before aggregation,
driver memory fell from **22,490,928 to 110,912 bytes**; ETS separately retained
20,165,448 bytes. The list driver recorded six 6–12 ms GC pauses during issuance.
ETS driver GC events appeared only in collection/aggregation after timing stopped.
Both completed every request. Their p99 was 10.637 and 15.002 ms respectively:
this establishes a heap/GC improvement, not a latency win from those two runs.

**A separate BEAM was not a separate machine.** The original fixture and client
each had four schedulers on a Linux machine with only four physical cores. Fresh
single-client repetitions on that same machine could pass: the diagnostic
TypeSafe and Finch runs completed all 90,000 calls with p99 7.085 and 8.024 ms.
Using the unchanged library and original harness, moving the fixture to macOS
over an SSH reverse tunnel produced three passing 6,000 req/s runs each for
TypeSafe, Finch, and Req. Their p99 ranges were 8.20–9.41, 9.30–10.56, and
8.96–9.85 ms respectively. ReqLLM still saturated. This supports resource
contention as a contributor; the topology trials were sequential, so they are
not a randomized causal estimate of its size.

**The Linux host also changes under sustained stress.** During the expanded
comparison, the monitored final 279 seconds reached 91–100°C and the package
thermal-throttle counter increased by 103. Monitoring started partway through
the run; it did not cover the earlier cases. Later repetitions slowed for multiple clients even with the fixture
on another machine. Counter changes demonstrate actual throttle events, rather
than merely a hot CPU. They do not establish how much of a given request's
latency came from throttling, and no corresponding counters were captured for
the historical run. The SSH forwarding process also consumes client-host CPU.
macOS retained ordinary desktop/background activity. These are development
machines, not isolated benchmark appliances.

## Avoidable work in TypeSafe

The previous upload fast path covered encoded bodies up to 32 KiB. The mixed
workload's 64 KiB state exceeds that limit after encoding and was sent in 16 KiB
steps. Each extra step can incur a TLS send, continuation message, and revisit
of pending uploads. Mint can split a larger send into legal HTTP/2 DATA frames.

The candidate uses at most 64 KiB per step for encoded bodies up to 128 KiB,
always respecting stream and connection flow-control credit. Larger bodies
retain 16 KiB steps throughout. This bounds the scheduling change rather than
letting arbitrary uploads monopolize a connection. API behavior, native JSON,
response validation, cancellation, deadlines, and dependencies are unchanged.

The 128 KiB boundary is a conservative implementation choice, not an experimentally
established optimum. TLS tests cover blocked 100,000-byte and 200,000-byte states,
legal DATA frame sizes, a healthy concurrent stream, deadline expiry, and caller
termination. A separate one-connection guard compares small-request tails alongside
100,000-byte and 512 KiB states.

The function-count profile processed 5,081 submissions per version, including
warmup/startup. `upload/2` calls fell from 16,117 to 13,220, and `send_chunk/4`
attempts from 14,252 to 13,119. Some attempts have no flow-control credit and do
not send data, so these are not TLS-write counts. The profile supports reduced
scheduling work; its throughput is not ranking evidence.

## Expanded comparison results

Scheduled-arrival p99 ranges across three 15-second repetitions; a pass includes
all latency, lag, success, and drop criteria, not just p99. Every client was
offered the same work. These results retain the host instability described above.

| Offered req/s | Committed TypeSafe | Candidate TypeSafe | Finch | Req | ReqLLM |
|---:|---|---|---|---|---|
| 6,000 | 8.94–9.07 ms; 3/3 | 9.02–9.80 ms; 3/3 | 8.87–159.82 ms; 1/3 | 9.83–208.49 ms; 1/3 | 508.49–614.77 ms; 0/3 |
| 8,000 | 9.05–58.57 ms; 1/3 | 9.78–22.98 ms; 2/3 | 9.07–371.49 ms; 1/3 | 196.69–381.01 ms; 0/3 | 493.31–699.70 ms; 0/3 |
| 10,000 | 53.28–130.33 ms; 0/3 | 10.13–109.05 ms; 1/3 | 291.18–358.68 ms; 0/3 | 290.24–380.38 ms; 0/3 | 445.82–685.41 ms; 0/3 |

At 6,000 req/s both TypeSafe versions completed all 270,000 offered requests.
The candidate used a median 5,274 BEAM reductions per successful request versus
5,888 for the baseline, about **10.4% less client-VM work by this metric**. CPU
time ranges overlapped (candidate 504–520 versus baseline 506–516 ms per 1000
successful requests), and candidate p99 was slightly higher. Fewer reductions
are not proof of lower CPU time or latency.

At 8,000 req/s the candidate completed all 360,000 offered requests; the baseline
dropped 14. The candidate's third p99 still missed the 20 ms limit. At 10,000
req/s the candidate dropped 14,801 calls versus 14,000 for the baseline, and its
median p99 was worse, despite one passing repetition. **Neither version has a
higher qualifying rate than 6,000 in this grid.** The mixed high-rate findings
are inconclusive as a general latency or capacity improvement; the retained
claim is reduced upload work, not a universal speedup.

Both one-connection guards passed all three 15-second repetitions per version,
with no errors or drops. With 100,000-byte states at 2,000 offered req/s,
small-request scheduled p99 ranged from 8.91–12.04 ms before to 8.84–9.54 ms
after. With 512 KiB states at 1,000 req/s, it ranged from 10.42–10.88 ms before
to 10.38–10.53 ms after. These overlapping ranges provide no evidence of a tail
regression in the tested guards, not a guarantee for every payload or load.

The bounded upload change is retained for its measured reduction in work and
passing protocol/fairness checks. It is not presented as a proven latency or
capacity increase. The main comparison and guards contain 5,670,000 offered
requests, with every failed/dropped request retained in the reports.

## Comparison method and evidence

The expanded comparison uses a fresh client VM per scenario and randomized
complete blocks (seed 20260917), with all repetitions retained. The committed
baseline is `4d9fff4`; baseline and candidate use the same updated Elixir harness,
locks, four connections, 128 active streams and 1024 queued calls per TypeSafe
connection, a 512-request driver bound, and a 1000 ms timeout. Finch uses the
same four connections but its own admission semantics. ReqLLM includes additional
SDK work as described in [README](README.md#req-and-reqllm-adapters).

Linux is an Intel i5-1135G7; the fixture runs on an Apple M4 Max. Both use
Elixir 1.20.4 / OTP 29.0.6 and four BEAM schedulers. The fixture is verified TLS,
HTTP/2, a synthetic 5 ms delay, and no live service calls. The reverse SSH tunnel
connects Linux localhost:8452 to macOS localhost:8452. This is not ordinary
direct network transport and does not establish live Jev performance.

Each main scenario offers traffic for 15 seconds at 6,000, 8,000, or 10,000
requests/s, in a periodic nine-small/one-large mix: 256-byte and 64 KiB states,
one Noul question each. There are three repetitions for each of five variants:
committed TypeSafe, candidate TypeSafe, Finch, Req, and ReqLLM. The latency screen
remains scheduled-arrival p99 ≤20 ms, launch-lag p99 ≤5 ms, no errors or drops,
at least 1000 successful samples, and ≥99% of offered work within 20 ms.

Use [complete tables](MIXED-DATA.md), [raw evidence and checksums](recorded/mixed-root-cause/manifest.json),
and [reproduction instructions](README.md#mixed-load-investigation) together.
The original topology diagnostic predates configurable fixture descriptions:
its raw `environment.fixture` default says localhost even though the fixture
was physically on macOS. The evidence manifest records this correction without
altering the original file. Profiled runs diagnose work; they are not rankings.

## What remains unproven

These runs cannot establish a universal lowest-latency client, a reliable maximum
capacity on this Linux host, or a production req/s figure for Jev. A stronger
release comparison needs dedicated, thermally stable client hardware, direct
network access to a separate fixture, host observations from the start of every
run, and representative request/response distributions and durations. All clients
must use the same conditions; successful-only percentiles must be accompanied by
errors, drops, and both request classes. The [claim policy](CLAIMS.md) still applies.

Validation: 60 root tests/doctests on macOS and Linux, 25 benchmark tests on each,
benchmark smoke, full project quality checks (including Credo/ex_slop, ex_dna,
Credence, and Dialyzer) on both hosts, and ExDoc with warnings treated as errors.
