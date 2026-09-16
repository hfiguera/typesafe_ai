%{
  configs: [
    %{
      name: "default",
      files: %{included: ["lib/", "test/", "mix.exs"]},
      strict: true,
      plugins: [{ExSlop, []}]
    }
  ]
}
