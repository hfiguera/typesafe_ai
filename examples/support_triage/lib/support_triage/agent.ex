defmodule SupportTriage.Agent do
  @moduledoc "A ticket's accumulated messages and immutable evaluation history."
  use Jido.Agent,
    name: "support_triage",
    description: "Uses Jev's structured evaluations to simulate support routing",
    schema: [
      messages: [type: {:list, :string}, default: []],
      history: [type: {:list, :map}, default: []]
    ]

  @doc "Adds customer information and evaluates the full conversation once."
  def submit(agent, message, opts \\ []) do
    if String.trim(message) == "" do
      {:error, :empty_message}
    else
      context = %{
        client: Keyword.get(opts, :client, SupportTriage.Client),
        timeout: Keyword.get(opts, :timeout, 30_000),
        policy: Keyword.get(opts, :policy, [])
      }

      instruction = %Jido.Instruction{
        action: SupportTriage.Evaluate,
        params: %{message: message},
        context: context
      }

      # TypeSafe owns the deadline and retry policy. An outer retry could bill twice.
      case cmd(agent, instruction,
             timeout: 0,
             max_retries: 0
           ) do
        {updated, []} -> {:ok, updated}
        {_unchanged, _directives} -> {:error, :workflow_failed}
      end
    end
  end
end
