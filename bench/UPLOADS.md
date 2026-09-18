# Bounded upload fast path — 2026-09-17

Historical experiment: this report describes the 32 KiB fast path retained in
`4d9fff4`. The subsequent [mixed-load investigation](MIXED.md) extends the
bounded path and records its evidence and limitations separately.

The retained change lets an **encoded body up to 32 KiB** finish in one body send
when the HTTP/2 window permits. Larger bodies retain the original **16 KiB** send
budget throughout the upload. Mint still splits sends into legal protocol frames.
There is no new option or dependency, and no change to response validation,
deadlines, cancellation, response limits, or retry rules.

## Why this change

The previous implementation split every body at 16 KiB and scheduled a continuation
message. With many concurrent moderately sized bodies, pending-upload scans revisited
those scheduled requests repeatedly. Sending the complete moderate body removes
that continuation and keeps it out of subsequent pending-upload scans.

The 16 KiB state / 32-question benchmark crosses the old boundary once the JSON
question definitions and envelope are included. Separating state size and question
count confirmed that the boundary, rather than JSON decoding alone, mattered.
The Finch adapter already uses our same native JSON and typed response validation.

Initial experiments increased the send budget for all bodies to 64 KiB, then
32 KiB. Both helped batch throughput, but mixed fixed-rate runs showed a possible
small-request tail-latency cost on a single connection. The retained fast path
therefore leaves scheduling for bodies larger than 32 KiB unchanged. This is a
conservative bound, not a claim that 32 KiB is optimal for every workload.

## Method

Before: commit `4982f5e` (16 KiB uploads). After: the current bounded fast path.
Both use the same expanded harness. Hardware and runtime match [RESULTS.md](RESULTS.md):
Apple M4 Max on macOS and i5-1135G7 on Linux; Elixir 1.20.4 / OTP 29.0.6, four
schedulers each for the client and separate HTTPS fixture. Verified TLS, forced
HTTP/2, no artificial delay, no real API calls. The fixture shares host CPU.

Homogeneous matrices use up to 128 caller tasks, 128 stream slots per connection,
one/four connections, and 3,000 measured calls × three repetitions. Every matrix
includes Finch controls and randomized scenario order. Before/after run in separate
VMs; mixed matrices reverse version order. Values are medians of individual runs,
including p99, not pooled percentiles. Host drift and task-driver scheduling remain
limitations, particularly on Linux; the results do not establish real Jev latency.

## Batch result: 16 KiB state, 32 questions

| Host | Connections | Before calls/s | After calls/s | Finch in after run | Before p99 ms | After p99 ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| mac | 1 | 11,990 | 15,070 | 13,437 | 11.393 | 10.646 |
| mac | 4 | 23,040 | 24,621 | 23,658 | 13.968 | 11.435 |
| linux | 1 | 5,144 | 4,502 | 3,942 | 32.999 | 32.542 |
| linux | 4 | 6,691 | 5,825 | 5,143 | 49.344 | 43.193 |

macOS batch throughput increased about 26% with one connection and 7% with four;
the after medians exceed Finch by about 12% and 4%, respectively. The TypeSafe
after ranges were 14,477–15,206 and 24,597–25,578 calls/s; Finch's were
13,273–13,545 and 23,656–23,882 in those same matrices.

Linux slowed across matrices for both clients. Its before/after throughput
therefore **does not establish an absolute speedup**: TypeSafe fell from
5,144 to 4,502 (one connection), while Finch fell from 4,727 to 3,942.
The after TypeSafe median exceeded the same-matrix Finch median, but host drift
and the small number of repetitions limit that comparison. No cause for the
host slowdown was isolated. These are workload-specific results, not universal
superiority over Finch.

## Separate state size and question count

macOS, one connection; median successful calls/s:

| State bytes | Questions | Before | After | Finch in after run |
| ---: | ---: | ---: | ---: | ---: |
| 256 | 1 | 21,055 | 22,007 | 20,209 |
| 256 | 32 | 18,037 | 18,711 | 16,755 |
| 16,000 | 1 | 17,231 | 17,247 | 15,489 |
| 16,400 | 1 | 12,694 | 16,825 | 14,747 |
| 16,384 | 1 | 12,785 | 16,825 | 15,084 |
| 16,384 | 32 | 11,990 | 15,070 | 13,437 |

## Mixed traffic at equal offered load

Five alternating before/after repetitions, 10,000 calls each, 90% small (256 bytes,
one question) and 10% large (512 KiB, one question), no artificial server delay.
macOS offers 5,000 calls/s; Linux 2,000 calls/s. Both versions use the same rate,
128 streams and 1,024 queue slots per connection, a 512-call driver bound and a
5 s deadline. Small-request latency is reported separately; scheduled-arrival
latency includes the driver and excludes no waiting before the caller starts.

| Host | Connections | Before small API p99 ms | After small API p99 ms | Before scheduled p99 ms | After scheduled p99 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| mac | 1 | 0.810 | 0.942 | 2.269 | 2.303 |
| mac | 4 | 0.421 | 0.427 | 1.875 | 2.020 |
| linux | 1 | 1.590 | 1.593 | 2.654 | 2.520 |
| linux | 4 | 1.049 | 0.868 | 2.674 | 2.339 |

All paired calls succeeded, with zero driver drops. macOS small-request p99
rose slightly in this sample (API: +0.132 ms / +0.006 ms for one/four connections);
Linux was essentially unchanged or lower. This is not evidence that small-request
latency can never regress. Millisecond-scale scheduling
jitter is visible in the raw reports; small changes in these p99 estimates should
not be treated as guarantees. The large request follows the same 16 KiB upload
schedule before and after. The separate closed-loop mixed matrices also record
both classes' latency and outcomes for 16 KiB/32-question and 512 KiB/one-question
large calls; they are not equal-arrival-rate latency comparisons.

## Profiling evidence

The included `tprof` reports cover 2,261 batch calls (2,000 measured plus startup
and warmup), one connection. They trace selected TypeSafe/Mint/Finch modules and
spawned callers/workers. Untraced callees contribute to their traced parents;
connection negotiation is included. Heap words are not peak memory or all binary
allocations. Never use throughput printed by a profiled run as a speed ranking.

In the time profile, `upload/2` calls fell from 209,808 to 4,522 and Mint send
calls from 9,045 to 6,784, while DATA-frame encoding calls stayed at 6,783.
In the separate memory profile, heap words attributed to `flush_uploads/1` fell
from 1,053,328 to 32,637. These diagnose less scheduling/scanning and fewer
socket sends, rather than reduced validation or fewer protocol frames.

- [Before function time](recorded/mac-upload-profile-before-call_time.txt)
- [After function time](recorded/mac-upload-profile-after-call_time.txt)
- [Before heap allocation](recorded/mac-upload-profile-before-call_memory.txt)
- [After heap allocation](recorded/mac-upload-profile-after-call_memory.txt)

## Validation and reproduction

Tests explicitly hold back HTTP/2 flow-control credit, verify legal DATA frame
sizes, let a healthy stream finish during a stalled upload, and cancel that upload
by both deadline and caller termination. The HTTP/1 upload and existing retry,
pool, response-validation, and cancellation tests remain in place.

Run [upload_comparison.sh](upload_comparison.sh) with a clean baseline checkout and
a separate fixture; see [the commands and profiling scope](README.md#upload-scheduling-experiments).
Current raw source and harness fingerprints plus file checksums are recorded in
[the manifest](recorded/manifest.json). The earlier 64 KiB exploratory matrices
are retained with `64k` filenames; they do not describe the shipping code.

Raw matrices:

- [mac-upload-before.json](recorded/mac-upload-before.json)
- [mac-upload-before-mixed.json](recorded/mac-upload-before-mixed.json)
- [mac-upload-after.json](recorded/mac-upload-after.json)
- [mac-upload-after-mixed.json](recorded/mac-upload-after-mixed.json)
- [mac-upload-64k.json](recorded/mac-upload-64k.json)
- [mac-upload-64k-mixed.json](recorded/mac-upload-64k-mixed.json)
- [linux-upload-before.json](recorded/linux-upload-before.json)
- [linux-upload-before-mixed.json](recorded/linux-upload-before-mixed.json)
- [linux-upload-after.json](recorded/linux-upload-after.json)
- [linux-upload-after-mixed.json](recorded/linux-upload-after-mixed.json)
- [linux-upload-64k.json](recorded/linux-upload-64k.json)
- [linux-upload-64k-mixed.json](recorded/linux-upload-64k-mixed.json)

The manifest also lists all 40 paired-arrival reports, including individual
latencies, outcomes, maximum driver scheduling lag, and source fingerprints.
