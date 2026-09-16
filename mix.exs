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
      package: [files: ["lib", "guides", "mix.exs", "README.md", "CHANGELOG.md", "DESIGN.md"]],
      docs: docs(),
      dialyzer: [
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts",
        plt_add_apps: [:mix, :credence]
      ]
    ]
  end

  def application, do: [extra_applications: [:logger, :ssl, :public_key, :inets]]

  defp docs do
    [
      main: "readme",
      filter_modules: ~r/^Elixir\.TypeSafe(?:\.|$)/,
      # Markdown exports retain relative source links instead of rewriting them.
      assets: %{"guides" => "guides"},
      extras: [
        {"README.md", title: "Overview"},
        "guides/getting-started.md",
        "guides/configuration.md",
        "guides/errors-and-retries.md",
        "guides/telemetry.md",
        "guides/examples.md",
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        "Start here": ["README.md", "guides/getting-started.md"],
        Guides: ~r/guides\//,
        Releases: ["CHANGELOG.md"]
      ],
      groups_for_modules: [
        "Client API": [TypeSafe, TypeSafe.Client, TypeSafe.Question],
        Results: [
          TypeSafe.Response,
          TypeSafe.Answer.Choice,
          TypeSafe.Answer.Score,
          TypeSafe.Answer.Noul
        ],
        "Errors and retries": [TypeSafe.Error, TypeSafe.Retry]
      ]
    ]
  end

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
