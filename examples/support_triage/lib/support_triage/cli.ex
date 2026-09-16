defmodule SupportTriage.CLI do
  @moduledoc "Interactive terminal demo and repeatable sample/batch commands."
  alias SupportTriage.{Agent, Batch, Samples, View}

  @usage """
  Usage: mix triage [--batch | --sample ID [--follow-up]]
                    [--confidence 0.65] [--probability 0.8]
  Samples: duplicate, outage, ambiguous, sales
  With no mode flag, opens the interactive menu. Each evaluation makes one real
  TypeSafe request. Set TYPESAFE_API_KEY; no other provider key is needed.
  """

  def run(args, opts \\ []) do
    case parse(args) do
      {:ok, flags} ->
        run_flags(flags, opts)

      :error ->
        IO.puts(@usage)
        {:error, :invalid_arguments}
    end
  end

  defp parse(args) do
    {flags, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          batch: :boolean,
          sample: :string,
          follow_up: :boolean,
          help: :boolean,
          confidence: :float,
          probability: :float
        ]
      )

    if rest == [] and invalid == [] and valid_flags?(flags), do: {:ok, flags}, else: :error
  end

  defp valid_flags?(flags) do
    valid_mode?(flags) and
      Enum.all?([:confidence, :probability], fn key ->
        value = Keyword.get(flags, key, 0.5)
        value >= 0 and value <= 1
      end)
  end

  defp valid_mode?(flags) do
    not (Keyword.get(flags, :batch, false) and not is_nil(flags[:sample])) and
      (not Keyword.get(flags, :follow_up, false) or not is_nil(flags[:sample])) and
      (is_nil(flags[:sample]) or not is_nil(Samples.fetch(flags[:sample])))
  end

  defp run_flags(flags, opts) do
    cond do
      flags[:help] ->
        IO.puts(@usage)

      is_nil(GenServer.whereis(Keyword.get(opts, :client, SupportTriage.Client))) ->
        IO.puts("Set TYPESAFE_API_KEY before running this demo. No other API key is needed.")
        {:error, :missing_key}

      true ->
        IO.puts("Support decision agent — live TypeSafe evaluations; routing is simulated.")
        policy = Keyword.take(flags, [:confidence, :probability])
        execute(flags, Keyword.put(opts, :policy, policy))
    end
  end

  defp execute(flags, opts) do
    cond do
      flags[:batch] -> Samples.all() |> Batch.run(opts) |> Batch.report()
      flags[:sample] -> sample(Samples.fetch(flags[:sample]), flags[:follow_up], opts)
      true -> choose(opts)
    end
  end

  defp choose(opts) do
    IO.puts("\nChoose a ticket:")

    Enum.with_index(Samples.all(), 1)
    |> Enum.each(fn {sample, index} -> IO.puts("#{index}. #{sample.title}") end)

    IO.puts("5. Enter your own\n0. Quit")

    case read("Choice: ") do
      input when input in ["1", "2", "3", "4"] ->
        ticket = Enum.at(Samples.all(), String.to_integer(input) - 1)
        interactive_submit(Agent.new(), ticket.message, opts)

      "5" ->
        custom(opts)

      input when input in ["0", :eof] ->
        :ok

      _other ->
        IO.puts("Choose a number from 0 to 5.")
        choose(opts)
    end
  end

  defp custom(opts) do
    case read("Customer message: ") do
      :eof -> :ok
      text -> interactive_submit(Agent.new(), text, opts)
    end
  end

  defp interactive_submit(agent, message, opts) do
    case submit(agent, message, opts) do
      {:ok, updated} -> menu(updated, opts)
      {:error, _reason} -> menu(agent, opts)
    end
  end

  defp menu(agent, opts) do
    IO.puts(
      "\n1. Add customer information\n2. View all evaluations\n3. View decision history\n4. Start another ticket\n0. Quit"
    )

    case read("Choice: ") do
      "1" ->
        follow_up(agent, opts)

      "2" ->
        View.all(List.last(agent.state.history))
        menu(agent, opts)

      "3" ->
        View.history(agent)
        menu(agent, opts)

      "4" ->
        choose(opts)

      input when input in ["0", :eof] ->
        :ok

      _other ->
        IO.puts("Choose a number from 0 to 4.")
        menu(agent, opts)
    end
  end

  defp follow_up(agent, opts) do
    case read("Additional customer information: ") do
      :eof -> :ok
      message -> interactive_submit(agent, message, opts)
    end
  end

  defp sample(ticket, follow_up?, opts) do
    with {:ok, first} <- submit(Agent.new(), ticket.message, opts),
         :ok <- result(first),
         {:ok, updated} <- sample_follow_up(first, ticket, follow_up?, opts) do
      result(updated)
    end
  end

  defp sample_follow_up(agent, ticket, true, opts), do: submit(agent, ticket.follow_up, opts)
  defp sample_follow_up(agent, _ticket, _follow_up?, _opts), do: {:ok, agent}

  defp submit(agent, message, opts) do
    IO.puts("\nEvaluating with Jev…")

    case Agent.submit(agent, message, opts) do
      {:ok, updated} ->
        View.show(List.last(updated.state.history), List.last(agent.state.history))
        {:ok, updated}

      {:error, reason} ->
        IO.puts("Could not evaluate: #{reason}.")
        {:error, reason}
    end
  end

  defp result(agent) do
    case List.last(agent.state.history).result do
      {:ok, _response} -> :ok
      {:error, _error} -> {:error, :evaluation_failed}
    end
  end

  defp read(prompt) do
    case IO.gets(prompt) do
      value when is_binary(value) -> String.trim(value)
      _other -> :eof
    end
  end
end
