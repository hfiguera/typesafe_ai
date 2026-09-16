# Support triage and evaluation

The [repository](https://github.com/hfiguera/typesafe_ai) includes a standalone
application in `examples/support_triage`.
It uses Jido core for agent state transitions and TypeSafe for evaluating
support tickets. Explicit Elixir policy rules choose simulated routes.

It needs **only `TYPESAFE_API_KEY`**. No second LLM provider, `jido_ai`, database,
or payment integration is required. The example lives in the complete source
checkout; it is not included in the installed Hex package. Its
[README](https://github.com/hfiguera/typesafe_ai/blob/main/examples/support_triage/README.md)
and [evaluation guide](https://github.com/hfiguera/typesafe_ai/blob/main/examples/support_triage/EVALUATION.md)
contain the full workflow and metric definitions.

## Run an interactive ticket

From the repository root, with the API key in your environment:

```sh
cd examples/support_triage
mix deps.get
mix deps.compile
mix triage
```

Pick a sample or enter a ticket. The application batches eleven Choice, Score,
and Noul questions into one evaluation. It shows the department, urgency, refund
probability, selected route, policy rule, model, latency, and token usage.

Use the menu to add customer information, inspect probability distributions and
score legends, view history, or start another ticket. A follow-up evaluates all
messages together and shows how the answers and route changed.

You can also run scripted demonstrations from the same directory:

```sh
mix triage --sample duplicate
mix triage --sample duplicate --follow-up
mix triage --batch
mix triage --help
```

These commands make real, potentially billable evaluations. Retries are disabled
in both the TypeSafe calls and the Jido command. Ticket text and results are
visible in the terminal. Routes are simulated: a refund route assigns review;
it does not issue a payment or contact a customer.

## Measure the same workflow

The evaluation command exercises the same agent and policy, with labels withheld
from the model. The bundled datasets contain 10 synthetic development tickets
and 8 synthetic held-out tickets, including multi-message cases:

```sh
mix triage.eval --dataset datasets/support.jsonl --output results/development.json
mix triage.eval --dataset datasets/support_held_out.jsonl --output results/held-out.json
```

It reports department correctness separately from final route correctness,
automatic routing coverage and mistakes, required human review recall, failures,
latency percentiles, and observed input/output tokens. A correct department can
still result in an incorrect final route if the policy defers unnecessarily or
another evaluated signal changes the decision.

Saved JSON includes per-ticket outcomes, model identifiers, dataset and question
fingerprints, policy fingerprint, thresholds, and runtime information. It does
not contain the API key or customer message text. Existing result files are not
overwritten; use a fresh output path for each run or omit `--output` to generate
one automatically. Results are ignored by Git.

Use development data to choose prompts and thresholds, then freeze those choices
before evaluating held-out data. These small synthetic sets are regression aids,
not evidence of real-world accuracy. Latency includes queueing and connection
setup; observed usage can omit failed or interrupted evaluations. Review labels
and use representative tickets before drawing broader conclusions.

## Validate locally without credentials

From the example directory:

```sh
mix test
mix quality
```

After dependencies are installed, tests run offline against local protocol
fixtures. They exercise the real Jido action, TypeSafe client, routing rules,
evaluation arithmetic, and failure behavior. CI never runs the live labeled
evaluations automatically.
