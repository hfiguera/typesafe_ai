# Getting started

TypeSafe evaluates shared context against your questions and returns typed
decisions. The Elixir client uses Mint over HTTP/1 or HTTP/2. It requires
**Elixir 1.18+ and Erlang/OTP 27+**, and uses native `JSON` for encoding.

## Install

Add `typesafe_ai` to your application's dependencies in `mix.exs`:

```elixir
defp deps do
  [{:typesafe_ai, "~> 0.1.1"}]
end
```

To use the development version from the
[GitHub repository](https://github.com/hfiguera/typesafe_ai) instead:

```elixir
{:typesafe_ai, git: "https://github.com/hfiguera/typesafe_ai.git", branch: "main"}
```

Then run `mix deps.get`. The package and OTP application are named `typesafe_ai`;
the public module namespace is `TypeSafe`.

When working on the library alongside another application, you can instead use
`{:typesafe_ai, path: "../typesafe_ai"}`, adjusting the path to your local checkout.

## Start a supervised client

Set `TYPESAFE_API_KEY` in the environment using your usual secret provisioning.
Read it in your application and pass it explicitly to the client:

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {TypeSafe.Client,
       name: MyApp.TypeSafe,
       api_key: System.fetch_env!("TYPESAFE_API_KEY")}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
```

Add this child to your existing supervision tree if the application already has
one. A new application also needs `mod: {MyApp.Application, []}` in the list
returned by its `application/0` function in `mix.exs`.

The client validates its configuration at startup, but connects on the first
evaluation. Successful startup does not verify the key with the service. The
library never reads environment variables or macOS Keychain itself. See
[configuration](configuration.md) for release runtime configuration and multiple
clients.

## Evaluate shared context

With your application running, this makes one live evaluation:

```elixir
result =
  TypeSafe.system_one(MyApp.TypeSafe,
    state: %{message: "I was charged twice. Please refund the duplicate payment."},
    questions: %{
      "team" =>
        TypeSafe.choice("Which team should handle this?", %{
          "billing" => "Payments, invoices, and refunds",
          "technical" => "Bugs and integration problems"
        }),
      "urgency" =>
        TypeSafe.score("How urgently should we respond?", [
          "Routine: can wait",
          "Needs attention today",
          "Immediate: work is blocked"
        ]),
      "refund" => TypeSafe.noul("Is a refund requested?")
    },
    timeout: 15_000,
    retry: [max_attempts: 1]
  )

case result do
  {:ok, %TypeSafe.Response{answers: answers, model: model, usage: usage}} ->
    %TypeSafe.Answer.Choice{choice: team} = answers["team"]
    %TypeSafe.Answer.Score{score: urgency} = answers["urgency"]
    %TypeSafe.Answer.Noul{noul: refund_probability} = answers["refund"]

    %{team: team, urgency: urgency, refund_probability: refund_probability,
      model: model, usage: usage}

  {:error, %TypeSafe.Error{kind: kind, status: status}} ->
    {:evaluation_failed, kind, status}
end
```

Results vary with the state, questions, and model. This example disables retries
to make the number of attempts explicit; normal clients default to at most three
attempts for HTTP 429 and 529 responses. Live evaluations use service quota and
may be billable.

## Choose the right question type

| Helper | Input | Result |
| --- | --- | --- |
| `TypeSafe.choice/2` | 1–255 named options | Selected label, full probabilities, confidence |
| `TypeSafe.score/2` | 2–10 ordered levels | Weighted zero-based level index, probabilities, legend, confidence |
| `TypeSafe.noul/2` | A yes/no question, optionally with explicit criteria | Probability of yes from 0 to 1 |

A three-level Score ranges from **0 to 2** and may fall between levels. Noul
returns a probability, not a Boolean, and has no separate confidence field.
Confidence is supplied by the service; it is not a measured guarantee of
correctness. Set application thresholds using representative evaluation data.

Question IDs, Choice labels, and probability/legend keys remain **strings**.
Use `answers["team"]`, not `answers[:team]`. Token usage is a map with atom keys
`:input_tokens` and `:output_tokens`, reported for the successful attempt only.

## Supply JSON-compatible input

State must be a string, map, or list. Nested values must be encodable with native
`JSON`. Instructions and criterion descriptions can also be maps or lists; they
do not need to be flattened into a text prompt. For example:

```elixir
TypeSafe.choice(
  %{task: "Choose a team", language: "Use the labels exactly as supplied"},
  %{"billing" => %{handles: ["payments", "refunds"]}, "technical" => nil}
)
```

Helpers only construct questions. `TypeSafe.system_one/2` validates the question
set and encodes input before contacting the client. Custom structs need conversion
to plain data or a native `JSON.Encoder` implementation; `Jason.Encoder` does not
apply. Missing inputs and invalid questions return a validation error.

Batch independent questions about the **same state** in one call, including
questions whose answers you might use only after choosing a route. For different
states, share a client across bounded tasks; see [configuration](configuration.md).
For an end-to-end application, see [the support triage example](examples.md).
