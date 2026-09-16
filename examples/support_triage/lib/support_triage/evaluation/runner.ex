defmodule SupportTriage.Evaluation.Runner do
  @moduledoc "Runs the same Jido workflow for every message and scores each ticket's final revision."
  alias SupportTriage.Agent

  def run(cases, opts \\ []) do
    {:ok, supervisor} = Task.Supervisor.start_link()
    longest = cases |> Enum.map(&length(&1["messages"])) |> Enum.max(fn -> 1 end)
    timeout = longest * (Keyword.get(opts, :timeout, 30_000) + 1_500) + 2_000

    try do
      supervisor
      |> Task.Supervisor.async_stream_nolink(cases, &evaluate(&1, opts),
        max_concurrency: Keyword.get(opts, :concurrency, 1),
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.zip(cases)
      |> Enum.map(fn
        {{:ok, result}, _ticket} -> result
        {{:exit, _reason}, ticket} -> failed(ticket, timeout)
      end)
    after
      Supervisor.stop(supervisor)
    end
  end

  defp evaluate(ticket, opts) do
    started = System.monotonic_time(:millisecond)

    {agent, error} =
      Enum.reduce_while(ticket["messages"], {Agent.new(), nil}, &step(&1, &2, opts))

    %{
      id: ticket["id"],
      expected: ticket["expected"],
      tags: ticket["tags"],
      message_count: length(ticket["messages"]),
      history: agent.state.history,
      error: error,
      duration_ms: System.monotonic_time(:millisecond) - started
    }
  end

  defp step(message, {agent, nil}, opts) do
    case Agent.submit(agent, message, opts) do
      {:ok, updated} -> continue(updated)
      {:error, reason} -> {:halt, {agent, reason}}
    end
  end

  defp continue(agent) do
    case List.last(agent.state.history).result do
      {:ok, _response} -> {:cont, {agent, nil}}
      {:error, error} -> {:halt, {agent, error.kind}}
    end
  end

  defp failed(ticket, timeout) do
    %{
      id: ticket["id"],
      expected: ticket["expected"],
      tags: ticket["tags"],
      message_count: length(ticket["messages"]),
      history: [],
      error: :worker_failed,
      duration_ms: nil,
      worker_timeout_ms: timeout
    }
  end
end
