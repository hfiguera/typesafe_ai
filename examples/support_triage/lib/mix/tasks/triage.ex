defmodule Mix.Tasks.Triage do
  @shortdoc "Run the Jido + TypeSafe support decision demo"
  @moduledoc "Run `mix triage --help` for interactive and batch options."
  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case SupportTriage.CLI.run(args) do
      :ok -> :ok
      {:error, reason} -> Mix.raise("Triage demo failed: #{reason}")
    end
  end
end
