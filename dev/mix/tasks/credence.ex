defmodule Mix.Tasks.Credence do
  @moduledoc "Checks library source with Credence, without rewriting files."
  use Mix.Task

  @shortdoc "Checks semantic and idiomatic code with strict Unicode assumptions"
  @impl true
  def run(args) do
    Mix.Task.run("compile", ["--warnings-as-errors"])
    paths = if args == [], do: Path.wildcard("lib/**/*.ex"), else: args

    findings = Enum.flat_map(paths, &analyze/1)
    Enum.each(findings, fn finding -> Mix.shell().error(finding) end)

    if findings == [] do
      Mix.shell().info("Credence: #{length(paths)} files checked, no findings")
    else
      Mix.raise("Credence found #{length(findings)} issues")
    end
  end

  defp analyze(path) do
    %{issues: issues} = Credence.analyze(File.read!(path), assumptions: :strict)

    Enum.map(issues, fn issue ->
      "#{path}:#{Map.get(issue.meta, :line, 1)}: #{inspect(issue.rule)}: #{issue.message}"
    end)
  end
end
