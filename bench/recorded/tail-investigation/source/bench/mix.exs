defmodule TypeSafe.Bench.MixProject do
  use Mix.Project

  def project do
    [
      app: :typesafe_bench,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: [
        {:typesafe_ai, path: System.get_env("TYPESAFE_BENCH_PATH", "..")},
        {:bandit, "~> 1.12"},
        {:finch, "~> 0.23.0"},
        {:req, "~> 0.7.4"},
        {:req_llm, "~> 1.24.0"}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger, :ssl]]
end
