# These timings include function-call and loop overhead; no network or credentials.
for count <- [1, 32, 128] do
  questions = Map.new(1..count, &{"q#{&1}", TypeSafe.noul("Is this true?")})
  input = [state: String.duplicate("x", 16_384), questions: questions]
  {:ok, prepared} = TypeSafe.Request.prepare(input)

  body =
    JSON.encode!(%{
      model: "jev-benchmark",
      usage: %{input_tokens: 12, output_tokens: 2},
      answers: Map.new(1..count, &{"q#{&1}", %{type: "noul", noul: 0.9}})
    })

  for {phase, call} <- [
        prepare: fn -> TypeSafe.Request.prepare(input) end,
        assemble: fn ->
          prepared |> TypeSafe.Request.body("jev-benchmark") |> IO.iodata_to_binary()
        end,
        decode_validate: fn -> TypeSafe.Response.decode(body, prepared.schema) end
      ] do
    for _ <- 1..1000, do: call.()

    samples =
      for _ <- 1..10_000 do
        {time, _result} = :timer.tc(call)
        time
      end

    IO.inspect(%{
      questions: count,
      phase: phase,
      latency_ms: TypeSafe.Bench.Runner.percentiles(samples)
    })
  end
end
