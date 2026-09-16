defmodule SupportTriage.Evaluation.Report do
  @moduledoc "Produces JSON artifacts and a concise terminal report without keys or ticket text."
  alias SupportTriage.Evaluation.{Dataset, Metrics}
  @policy_source "lib/support_triage/policy.ex"
  @external_resource @policy_source
  @policy_digest Dataset.digest(File.read!(@policy_source))

  def build(dataset, results, opts, started_at, wall_ms) do
    {:ok, questions} = TypeSafe.Question.to_wire(SupportTriage.Questions.all())

    %{
      schema_version: 1,
      started_at: started_at,
      wall_ms: wall_ms,
      dataset: Map.drop(dataset, [:cases]),
      selected_ids: Enum.map(results, & &1.id),
      requested_model: Keyword.fetch!(opts, :model),
      actual_models: models(results),
      policy: Map.new(Keyword.fetch!(opts, :policy)),
      policy_sha256: @policy_digest,
      questions_sha256: Dataset.digest(:erlang.term_to_binary(questions, [:deterministic])),
      questions: questions,
      concurrency: Keyword.fetch!(opts, :concurrency),
      request_timeout_ms: Keyword.fetch!(opts, :timeout),
      max_attempts: 1,
      runtime: %{
        elixir: System.version(),
        otp: System.otp_release(),
        architecture: to_string(:erlang.system_info(:system_architecture)),
        jido: version(:jido),
        typesafe_ai: version(:typesafe_ai)
      },
      summary: Metrics.summarize(results),
      cases: Enum.map(results, &serialize/1)
    }
  end

  def save(path, report) do
    File.write(path, JSON.encode_to_iodata!(report), [:exclusive])
  end

  def print(report) do
    s = report.summary
    IO.puts("\nDataset #{report.dataset.version} / #{report.dataset.split}: #{s.cases} tickets")
    IO.puts("Models: #{Enum.join(report.actual_models, ", ")}")
    IO.puts("Department correct: #{rate(s.department_correct)}")
    IO.puts("Final route correct: #{rate(s.route_correct)}")
    IO.puts("Automatic routing coverage: #{rate(s.automatic_coverage)}")

    IO.puts(
      "Inappropriate automatic routes: #{rate(s.inappropriate_automatic)} of automatic routes"
    )

    IO.puts("Required human review recall: #{rate(s.required_review_recall)}")
    IO.puts("Disposition counts: #{inspect(s.dispositions)}")
    IO.puts("Failures: #{s.failures} tickets; #{s.request_failures} recorded requests")

    IO.puts(
      "Request latency: median #{s.request_latency_ms.median || "n/a"} ms; p95 #{s.request_latency_ms.p95 || "n/a"} ms"
    )

    IO.puts("Observed token usage: #{s.tokens.input} in / #{s.tokens.output} out")

    IO.puts(
      "Latency includes queueing and connection setup. Failed requests may have unreported usage."
    )

    IO.puts(
      "Synthetic labels are provisional; this is a regression evaluation, not an accuracy claim."
    )
  end

  defp serialize(result) do
    result
    |> Map.put(:scores, Metrics.score(result))
    |> Map.update!(
      :history,
      &Enum.map(&1, fn entry ->
        entry
        |> Map.delete(:message)
        |> Map.update!(:result, fn response -> response(response) end)
      end)
    )
  end

  defp response({:ok, response}) do
    %{
      status: "ok",
      model: response.model,
      usage: response.usage,
      answers: Map.new(response.answers, fn {id, answer} -> {id, answer(answer)} end)
    }
  end

  defp response({:error, error}),
    do: %{status: "error", kind: error.kind, http_status: error.status}

  defp answer(%TypeSafe.Answer.Choice{} = answer),
    do: Map.put(Map.from_struct(answer), :type, "choice")

  defp answer(%TypeSafe.Answer.Score{} = answer),
    do: Map.put(Map.from_struct(answer), :type, "score")

  defp answer(%TypeSafe.Answer.Noul{} = answer),
    do: Map.put(Map.from_struct(answer), :type, "noul")

  defp models(results) do
    results
    |> Enum.flat_map(& &1.history)
    |> Enum.flat_map(fn
      %{result: {:ok, response}} -> [response.model]
      _failed -> []
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp version(app), do: app |> Application.spec(:vsn) |> to_string()
  defp rate(%{fraction: nil}), do: "n/a (0/0)"
  defp rate(rate), do: "#{Float.round(rate.fraction * 100, 1)}% (#{rate.count}/#{rate.total})"
end
