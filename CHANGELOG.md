# Changelog

## 0.1.1 — 2026-09-17

The existing evaluation API and default single-connection configuration are
preserved. Connection pooling is opt-in.

- Optional `pool_size` behind the existing client API, with supervised connection
  workers, per-connection limits, and HTTP/2 multiplexing on every connection.
- Skip full workers without replaying accepted requests; preserve deadlines,
  caller cancellation, response limits, and retry policies.
- Decode and validate responses in callers to avoid blocking other streams;
  retain deadline checks and emit correlated stop telemetry from the caller.
- Explicitly reject remote-node client references; deadlines use local monotonic time.
- Assemble request bodies in the caller and reuse the encoded body across retries.
- Keep validation schemas in the caller and transfer complete request bodies as
  binaries to reduce copying between caller and connection worker.
- Track only unfinished uploads and avoid queue scans on normal completion.
- Reduce upload scheduling for encoded request bodies up to 128 KiB with at most
  64 KiB steps, respecting flow-control credit and retaining 16 KiB steps for larger uploads.
- Enable TCP_NODELAY for latency-sensitive request writes.
- Separate offline benchmark project with fixed-arrival load tests, serialization
  timings, and Linux/macOS measurements.
- Reproducible latency-versus-load sweeps with per-repetition budget checks,
  driver diagnostics, bounded opt-in live measurements, and evidence rules for
  performance claims.
- Keep benchmark samples outside the arrival driver's heap, record per-second
  outcomes and latency, and measure fresh client VMs with host thermal observations.
- Document client capabilities, capacity limits, and workload tuning.

## 0.1.0 — 2026-09-16

- MIT license and Hex package metadata with repository links.
- System One evaluations with Choice, Score, and Noul helpers and typed answers.
- Supervised Mint HTTP/1 and HTTP/2 connection reuse, bounded work, deadlines,
  caller cancellation, and explicit retry policies.
- Native JSON, verified TLS, redacted errors/status, and request telemetry.
- Offline TCP/TLS/HTTP/2 integration tests, opt-in live smoke, and quality checks.
- Consumer guides, grouped API reference, and executable documentation examples.
- Jido support triage example with interactive tickets and labeled workflow
  evaluations, including separate development and held-out datasets.
