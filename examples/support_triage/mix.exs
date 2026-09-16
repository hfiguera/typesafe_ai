defmodule SupportTriage.MixProject do
  use Mix.Project

  def project do
    [
      app: :support_triage,
      version: "0.1.0",
      elixir: "~> 1.18",
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
      dialyzer: [
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts",
        plt_add_apps: [:mix, :credence]
      ]
    ]
  end

  def application, do: [extra_applications: [:logger], mod: {SupportTriage.Application, []}]

  defp elixirc_paths(:test),
    do: [
      "lib",
      Path.expand("../../dev", __DIR__),
      "test/support",
      Path.expand("../../test/support", __DIR__)
    ]

  defp elixirc_paths(:dev), do: ["lib", Path.expand("../../dev", __DIR__)]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:typesafe_ai, path: "../.."},
      {:jido, "~> 2.3.3"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4.4", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:credence, "~> 0.8.1", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
