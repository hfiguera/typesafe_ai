# Profiling changes execution speed. Never use profiled throughput as a ranking.
Path.wildcard(Path.join([to_string(:code.root_dir()), "lib", "tools-*", "ebin"]))
|> Enum.each(&Code.prepend_path/1)

mode = System.get_env("BENCH_PROFILE", "call_count")

case mode do
  "call_count" ->
    {:module, TypeSafe.Client} = :code.ensure_loaded(TypeSafe.Client)
    :cprof.start(TypeSafe.Client)

    try do
      TypeSafe.Bench.Runner.run(System.argv())
      :cprof.pause()
      IO.inspect(:cprof.analyse(TypeSafe.Client), limit: :infinity, label: "Client call counts")
    after
      :cprof.stop()
    end

  mode when mode in ["call_time", "call_memory"] ->
    modules = [
      TypeSafe.Client,
      TypeSafe.Request,
      TypeSafe.Response,
      Mint.HTTP,
      Mint.HTTP2,
      Finch.HTTP2.Pool,
      Finch.HTTP2.RequestStream
    ]

    for module <- modules, do: Code.ensure_loaded!(module)

    :tprof.profile(fn -> TypeSafe.Bench.Runner.run(System.argv()) end, %{
      type: if(mode == "call_time", do: :call_time, else: :call_memory),
      pattern: Enum.map(modules, &{&1, :_, :_}),
      report: {:total, {:measurement, :descending}}
    })
end
