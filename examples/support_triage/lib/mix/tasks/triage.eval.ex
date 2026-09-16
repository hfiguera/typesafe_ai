defmodule Mix.Tasks.Triage.Eval do
  @shortdoc "Evaluate labeled tickets using the Jido + TypeSafe workflow"
  @moduledoc "Run `mix triage.eval --help` for dataset and output options."
  use Mix.Task
  alias SupportTriage.Evaluation.CLI

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case CLI.run(args) do
      :ok -> :ok
      {:error, reason} -> Mix.raise("Evaluation failed: #{inspect(reason)}")
    end
  end
end
