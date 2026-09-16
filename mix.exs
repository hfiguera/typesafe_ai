defmodule TypeSafe.MixProject do
  use Mix.Project

  def project do
    [
      app: :typesafe_ai,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: [
        quality: [
          "format --check-formatted",
          "compile --warnings-as-errors",
          "credo --strict",
          "ex_dna",
          "credence",
          "dialyzer"
        ]
      ],
      description: "A supervised Mint client for the TypeSafe AI System One API",
      package: [files: ["lib", "mix.exs", "README.md", "CHANGELOG.md", "DESIGN.md"]],
      docs: [main: "readme", extras: ["README.md", "DESIGN.md"], assets: %{}],
      dialyzer: [
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts",
        plt_add_apps: [:mix, :credence]
      ]
    ]
  end

  def application, do: [extra_applications: [:logger, :ssl, :public_key, :inets]]

  defp elixirc_paths(:test), do: ["lib", "dev", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "dev"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:mint, "~> 1.10"},
      {:telemetry, "~> 1.3"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4.4", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:credence, "~> 0.8.1", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end
end
