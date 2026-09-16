defmodule SupportTriage.Evaluate do
  @moduledoc "Jido action that evaluates the ticket and records the routing decision."
  use Jido.Action,
    name: "evaluate_ticket",
    description: "Batch independent questions about a support conversation through TypeSafe",
    schema: [message: [type: :string, required: true]]

  alias SupportTriage.{Policy, Questions}

  @impl true
  def run(%{message: message}, context) do
    messages = context.state.messages ++ [message]
    started = System.monotonic_time(:millisecond)

    result =
      TypeSafe.system_one(context.client,
        state: %{customer_messages: messages},
        questions: Questions.all(),
        model: context.model,
        timeout: context.timeout,
        retry: [max_attempts: 1]
      )

    entry = %{
      revision: length(context.state.history) + 1,
      message: message,
      duration_ms: System.monotonic_time(:millisecond) - started,
      result: result,
      decision: decision(result, context.policy)
    }

    {:ok, %{messages: messages, history: context.state.history ++ [entry]}}
  end

  defp decision({:ok, response}, policy), do: Policy.decide(response, policy)
  defp decision({:error, _error}, _policy), do: nil
end
