defmodule TypeSafe.Bench.Summary do
  def print(path) do
    %{"results" => results} = path |> File.read!() |> JSON.decode!()

    keys =
      ~w(client protocol bytes questions delay concurrency connections max_concurrency max_queue large_every)

    groups = results |> Enum.group_by(&Map.take(&1, keys)) |> Enum.sort_by(&elem(&1, 0))

    IO.puts(
      "\n#{Path.basename(path)} — medians of individual repetitions, not pooled percentiles\n"
    )

    IO.puts(
      "| Client | Protocol | Bytes / questions | Delay | Callers | Connections | Large every | OK/s | p99 ms | Errors |"
    )

    IO.puts("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")

    for {c, runs} <- groups do
      rate = runs |> Enum.map(& &1["successful_rps"]) |> median() |> round()

      p99 =
        runs |> Enum.map(& &1["success_latency_ms"]["p99"]) |> Enum.reject(&is_nil/1) |> median()

      errors = Enum.sum(Enum.map(runs, &(&1["requests"] - Map.get(&1["outcomes"], "ok", 0))))

      IO.puts(
        "| #{c["client"]} | #{c["protocol"]} | #{c["bytes"]} / #{c["questions"]} | #{c["delay"]} | #{c["concurrency"]} | #{c["connections"]} | #{c["large_every"] || 0} | #{rate} | #{p99} | #{errors} |"
      )
    end
  end

  defp median([]), do: nil

  defp median(values) do
    values = Enum.sort(values)
    n = length(values)
    (Enum.at(values, div(n - 1, 2)) + Enum.at(values, div(n, 2))) / 2
  end
end

Enum.each(System.argv(), &TypeSafe.Bench.Summary.print/1)
