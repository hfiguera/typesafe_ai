# Labeled workflow evaluation

`mix triage.eval` measures the same Jido actions and TypeSafe calls used by the
interactive demo. It separates model department predictions from the final
decisions made by our Elixir routing policy.

From `examples/support_triage`, with `TYPESAFE_API_KEY` configured:

```sh
mix triage.eval --dataset datasets/support.jsonl --output results/baseline.json
```

On the development Mac, the existing Keychain item can supply the variable for
that command without printing the key:

```sh
TYPESAFE_API_KEY="$(/usr/bin/security find-generic-password -s typesafe_ai -a api_key -w)" \
  mix triage.eval --dataset datasets/support.jsonl --output results/baseline.json
```

Keep shell tracing disabled. No other provider or key is involved.

## Datasets and labels

The included datasets contain **synthetic, provisionally labeled tickets**:

- `datasets/support.jsonl`: 10 development tickets, 12 total messages.
- `datasets/support_held_out.jsonl`: 8 held-out tickets, 9 total messages.

They cover clear requests, ambiguity, conflicting instructions requiring human
review, changed priorities, clarification over multiple messages, and multilingual
requests. These are starter regression datasets, not independent evidence of
real-world accuracy. Review the labels and add representative, appropriately
de-identified tickets before making deployment decisions.

Each JSONL line is an independent ticket:

```json
{"id":"billing-001","dataset_version":"support-v1","split":"development","tags":["clear","billing"],"messages":["I was charged twice. Please refund the duplicate payment."],"expected":{"departments":["billing"],"routes":["refund_review"],"requires_human_review":false}}
```

`messages` is an ordered list of 1–20 non-empty customer messages. The runner
evaluates each message with all preceding context using the actual Jido agent.
**Labels apply to the final revision only.** Expected labels and tags are never
sent to the model. Processing a ticket stops at its first failure.

`departments` and `routes` list acceptable outcomes, so subjective cases may have
more than one correct answer. Valid departments are `billing`, `technical`,
`sales`, and `other`. Valid routes are `refund_review`, `troubleshoot`,
`contact_sales`, `incident_review`, `clarify`, and `human_review`.

If `requires_human_review` is true, the only acceptable route is `human_review`.
Otherwise, `clarify` or `human_review` can still be an acceptable option when
explicitly labeled. Avoid allowing every possible route: that conceals errors.
Scores and probabilities are retained for inspection, without comparing them to
invented exact numeric targets.

IDs must be unique. Each file must have a single non-empty dataset version and
one split (`development` or `held_out`). Empty or invalid datasets fail before
any API requests. Change the version when changing labels or examples. The report
also stores the SHA-256 of the exact source bytes, including whitespace.

## Metrics and denominators

| Metric | Definition |
| --- | --- |
| Department correct | Final Choice belongs to the acceptable department set / all selected tickets |
| Final route correct | Policy action belongs to the acceptable route set / all selected tickets |
| Automatic coverage | Automatically routed tickets / all selected tickets |
| Inappropriate automatic routing | Incorrect automatic routes / all automatic routes |
| Required review recall | Required-review tickets actually sent to human review / all required-review tickets |
| Dispositions | Counts of automatic routing, clarification, human review, and failures |

Automatic routing means `refund_review`, `troubleshoot`, `contact_sales`, or
`incident_review`. It means assigning a simulated work queue, **not performing a
refund or resolving an incident autonomously**. Clarification and specialist human
review are separate deferrals.

Failures count as incorrect in ticket-level quality metrics. They receive no
credit from an earlier successful revision. A zero denominator is `null` in JSON
and `n/a` in the terminal, never a misleading zero or 100%.

The JSON artifact includes request latency for all recorded attempts, latency
for successful requests separately, and end-to-end ticket latency. Median uses
the midpoint of the two central values for even samples; p95 uses nearest rank
(`ceil(0.95 * N)`). Latency includes queueing and connection setup. First requests
can therefore be slower than requests reusing a connection. Small sample p95 is
unstable; it is not a service performance guarantee.

Token totals include **all successful revisions**, including earlier revisions
of tickets that later failed. Failed requests may already have been billed and
may lack reported usage. If a worker crashes or exceeds its outer timeout, its
ticket is marked failed and partial measurements may be unavailable; absent
latency is omitted from percentile samples. Totals are observed usage, not a bill.

## Reproducible runs

```sh
# Default: sequential tickets, 30-second request deadline, one attempt
mix triage.eval --output results/baseline.json

# Compare a more conservative policy on the development set
mix triage.eval --confidence 0.80 --probability 0.90 \
  --missing-information 1.8 --output results/conservative.json

# Measure the same workload with four concurrent tickets
mix triage.eval --concurrency 4 --output results/concurrent.json

# Smoke-test only the first two tickets
mix triage.eval --limit 2

# After selecting prompts and thresholds on development data, evaluate held-out data
mix triage.eval --dataset datasets/support_held_out.jsonl \
  --output results/held-out.json
```

`--model` overrides the default `jev-latest`; use a service-supported fixed model
identifier when available. Actual response model identifiers are recorded, since
an alias can change. Thresholds accept 0–1 for confidence/probability and 0–3 for
missing information. Concurrency is 1–4; `--timeout` is 1–120000 milliseconds.

Use development data to select prompts and policy thresholds, then freeze those
choices before running the held-out file. Repeatedly tuning against held-out
results turns that file into development data. The bundled held-out data is kept
separate by this workflow; it is not an independently sourced benchmark.

Keep dataset fingerprints, selected IDs, model, and concurrency comparable when
interpreting changes. Repeated API evaluations can vary even with identical
settings. A fresh run with different thresholds also reruns the model; differences
are not necessarily caused solely by the policy. For policy-only analysis,
use the stored answers as fixed inputs to `SupportTriage.Policy.decide/2` after
decoding them into TypeSafe responses.

## Saved results

Every run writes JSON with schema version 1, including:

- Dataset version, split, filename, SHA-256, and selected ticket IDs.
- Requested/actual models, all effective thresholds, concurrency, timeout, and
  retry count (always one attempt).
- Question definitions and their fingerprint, policy source fingerprint, runtime
  versions/architecture, start time, and total elapsed time.
- Aggregate metrics plus each ticket's expected outcomes, tags, scores, and each
  recorded revision's typed answer data, decision, rule, latency, usage, or error.

The question fingerprint hashes its deterministic Erlang wire-map encoding; the
policy fingerprint hashes source bytes at compilation. No credentials, customer
message text, or raw API error bodies are written. Results still contain model
outputs and labels, so treat artifacts according to your data-handling needs.

Without `--output`, a unique filename is chosen under `results/`, which Git
ignores. Existing files are never overwritten. Reports are saved even when API
evaluations fail, and the command then exits unsuccessfully. An incorrect label
prediction alone does not cause a nonzero exit: it is an evaluation finding, not
a transport failure. Disk errors are reported rather than claiming a saved run.

Offline tests verify schema validation, label isolation, metric arithmetic,
multi-message accounting, result serialization, and failure behavior. They run
in the example's existing CI job without credentials. Held-out model evaluations
are never run automatically by tests or CI.
