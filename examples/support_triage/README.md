# Support decision agent

A standalone Mix application using **Jido 2.3** and the local `typesafe_ai`
library. Jev evaluates a ticket; explicit Elixir rules choose a simulated route.
Only **`TYPESAFE_API_KEY`** is required. There is no `jido_ai`, other LLM provider,
database, customer messaging, or payment integration.

Requires Elixir 1.18+ / OTP 27+. Run commands from this directory:

```sh
cd examples/support_triage
mix deps.get
mix deps.compile
mix triage
```

Provide `TYPESAFE_API_KEY` in the environment before starting the command. The
application reads it in `config/runtime.exs` and passes it to a supervised
`TypeSafe.Client`. On the development Mac, the existing Keychain item can supply
that environment variable for a single invocation without printing its value:

```sh
TYPESAFE_API_KEY="$(/usr/bin/security find-generic-password -s typesafe_ai -a api_key -w)" mix triage
```

Keep shell tracing (`set -x`) disabled when retrieving secrets. Retrieval is a
local shell convenience; the app itself only reads the environment variable.
The same variable works on Linux with your usual secret provisioning.

## Interactive flow

Choose a duplicate charge, service outage, ambiguous request, plan upgrade, or
enter your own ticket. The app makes one live API evaluation and displays:

- Department and confidence, urgency, and refund probability.
- The selected route and the exact application rule that selected it.
- The actual model, elapsed milliseconds, and input/output token counts.

Then use the menu to add customer information, inspect all eleven evaluations
(including probability distributions and score legends), view the decision
history, start another ticket, or quit. EOF also quits cleanly.

A follow-up sends all customer messages together. The next screen shows changed
answers and the old/new route. Results vary; confidence is the service's
distribution-derived metric, not a measured guarantee of correctness. The full
distributions are available in **View all evaluations**.

Every evaluation makes a real, billable request. Retries are disabled in both the
example's TypeSafe calls and the Jido command so a single step cannot silently
replay an evaluation. A failed step records the error and preserves history; it
does not reuse the previous route as a new decision. No key is placed in agent
state. Ticket text and results are intentionally visible in the terminal and
held in memory; use sample or non-sensitive text for demonstrations.

## Scripted demonstrations

```sh
# One evaluation
mix triage --sample duplicate

# Two evaluations; the follow-up says an outage is now the immediate problem
mix triage --sample duplicate --follow-up

# Four samples, evaluated concurrently through the same client
mix triage --batch

# Make automatic routing more conservative
mix triage --confidence 0.80 --probability 0.90

mix triage --help
```

Sample IDs are `duplicate`, `outage`, `ambiguous`, and `sales`. Batch output
includes each decision, elapsed time, token usage, expected department matches,
and aggregate usage for successful requests. Labels are illustrative and the
sample set is tiny; the match count is not an accuracy benchmark. Model output
may differ without indicating an SDK bug. Failed evaluations cause scripted
commands to exit unsuccessfully. A label mismatch alone does not fail the command.

## What Jev and Jido each do

`SupportTriage.Questions` batches these questions in one request:

| Type | Questions |
| --- | --- |
| Choice | Department, request type, next action, refund reason, failure category |
| Score | Urgency, frustration, missing information |
| Noul | Refund requested, blocking outage, specialist human review |

Refund reason and failure category are speculative branches: evaluate them
together with the main questions, then use the answer relevant to the chosen
route. This avoids an extra request solely to select a category after routing.

`SupportTriage.Agent` is a real `Jido.Agent` with a messages/history schema.
`SupportTriage.Evaluate` is a `Jido.Action` that calls the library and records a
revision. The CLI invokes `cmd/3` through `Agent.submit/3`; Jido owns the immutable
state transitions. It uses Jido's direct strategy and does not require a
long-running AgentServer for each terminal ticket. The TypeSafe connection has
its own supervisor. Batch evaluation runs independent agents in bounded tasks.

`SupportTriage.Policy` applies these rules in order:

1. Low department/action confidence → human review.
2. High specialist-review probability → human review.
3. Too much missing information → request details.
4. High blocking-outage probability plus urgency ≥ 2/3 → urgent incident review.
5. Consistent department/action/refund answers → the appropriate simulated route.
6. Otherwise → human review.

Default confidence/probability thresholds are 0.65/0.8; the missing-information
cutoff is 2/3. They are demo policy choices, not calibrated recommendations.
`Policy.decide(response, opts)` also supports `:missing_information` for callers.
Refunds always go to **review**; the app never issues payments.

This demonstrates batching, typed answers, probability-aware rules, speculative
branches, and decisions changing with new context. It doesn't establish model
accuracy or replace the library's protocol tests.

## Tests and quality checks

```sh
mix test
mix quality
```

Tests need no credentials or internet after dependencies are installed. The test
environment ignores `TYPESAFE_API_KEY`. Tests exercise the real Jido action and
TypeSafe client against the repository's local TCP fixture, with controlled
responses. They cover accumulated context, routing and threshold boundaries,
errors, timeouts, no duplicate retries, menu interaction, and batch reporting.

The example has its own dependency lockfile and quality configuration. `mix
quality` runs formatting, compilation with warnings as errors, Credo + ExSlop,
ExDNA, strict Credence, and Dialyzer. The Credence task and socket test helpers
are shared with the parent repository. Run this example from the complete checkout.

Jido's dependency tree includes Jason; the **TypeSafe client still uses native
JSON**. Some upstream dependencies currently emit compiler warnings on Elixir
1.20, including unused optional Lua/Phoenix integrations. These do not require
another service or key; the example's own compilation is checked separately with
warnings as errors.

References: [Jido core](https://jido.hexdocs.pm/readme.html),
[Jido actions](https://jido-action.hexdocs.pm/Jido.Action.html), and the root
`README.md` for TypeSafe client configuration and telemetry events.
