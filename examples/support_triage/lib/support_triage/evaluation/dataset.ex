defmodule SupportTriage.Evaluation.Dataset do
  @moduledoc "Loads versioned JSONL labels separately from the messages sent to Jev."
  @departments ~w(billing technical sales other)
  @routes ~w(refund_review troubleshoot contact_sales incident_review clarify human_review)

  def load(path) do
    with {:ok, bytes} <- File.read(path),
         {:ok, cases} <- decode(bytes),
         :ok <- consistent(cases) do
      [first | _rest] = cases

      {:ok,
       %{
         cases: cases,
         sha256: digest(bytes),
         version: first["dataset_version"],
         split: first["split"],
         path: Path.basename(path)
       }}
    end
  end

  def digest(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp decode(bytes) do
    bytes
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reject(fn {line, _number} -> String.trim(line) == "" end)
    |> Enum.reduce_while({:ok, []}, fn {line, number}, {:ok, acc} ->
      decode_line(line, number, acc)
    end)
    |> ordered()
  end

  defp decode_line(line, number, acc) do
    case JSON.decode(line) do
      {:ok, row} ->
        if valid?(row),
          do: {:cont, {:ok, [row | acc]}},
          else: {:halt, {:error, {:invalid_row, number}}}

      {:error, _reason} ->
        {:halt, {:error, {:invalid_json, number}}}
    end
  end

  defp ordered({:ok, rows}), do: {:ok, Enum.reverse(rows)}
  defp ordered(error), do: error

  defp valid?(%{
         "id" => id,
         "dataset_version" => version,
         "split" => split,
         "messages" => messages,
         "expected" => expected,
         "tags" => tags
       }) do
    nonempty?(id) and nonempty?(version) and split in ["development", "held_out"] and
      strings?(messages) and Enum.count_until(messages, 21) <= 20 and strings?(tags) and
      labels?(expected)
  end

  defp valid?(_row), do: false

  defp labels?(%{
         "departments" => departments,
         "routes" => routes,
         "requires_human_review" => required
       }) do
    choices?(departments, @departments) and choices?(routes, @routes) and is_boolean(required) and
      (not required or routes == ["human_review"])
  end

  defp labels?(_expected), do: false
  defp choices?(values, allowed), do: strings?(values) and Enum.all?(values, &(&1 in allowed))
  defp strings?([_ | _] = values), do: Enum.all?(values, &nonempty?/1)
  defp strings?(_values), do: false
  defp nonempty?(value), do: is_binary(value) and String.trim(value) != ""

  defp consistent([]), do: {:error, :empty_dataset}

  defp consistent(cases) do
    cond do
      Enum.uniq_by(cases, & &1["id"]) != cases -> {:error, :duplicate_ids}
      not single?(Enum.uniq_by(cases, & &1["split"])) -> {:error, :mixed_splits}
      not single?(Enum.uniq_by(cases, & &1["dataset_version"])) -> {:error, :mixed_versions}
      true -> :ok
    end
  end

  defp single?([_value]), do: true
  defp single?(_values), do: false
end
