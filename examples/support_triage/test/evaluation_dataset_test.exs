defmodule SupportTriage.Evaluation.DatasetTest do
  use ExUnit.Case, async: true
  alias SupportTriage.Evaluation.Dataset
  alias SupportTriage.EvaluationFixture, as: Fixture
  @moduletag :tmp_dir

  test "bundled development and held-out files have distinct IDs and content" do
    assert {:ok, dev} = Dataset.load("datasets/support.jsonl")
    assert {:ok, held} = Dataset.load("datasets/support_held_out.jsonl")
    assert dev.split == "development"
    assert held.split == "held_out"
    assert dev.sha256 != held.sha256
    all = dev.cases ++ held.cases
    assert Enum.uniq_by(all, & &1["id"]) == all
    assert Enum.uniq_by(all, & &1["messages"]) == all
    assert Enum.any?(all, & &1["expected"]["requires_human_review"])
    assert Enum.any?(all, &(Enum.count(&1["messages"]) > 1))
  end

  test "rejects malformed JSON with a physical line number", %{tmp_dir: dir} do
    path = Path.join(dir, "bad.jsonl")
    File.write!(path, "\nnot-json\n")
    assert {:error, {:invalid_json, 2}} = Dataset.load(path)
  end

  test "validates labels, messages and required-review consistency", %{tmp_dir: dir} do
    path = Path.join(dir, "bad.jsonl")
    row = Fixture.ticket()

    for invalid <- [
          %{},
          %{row | "messages" => []},
          %{row | "messages" => [" "]},
          %{row | "messages" => List.duplicate("message", 21)},
          put_in(row, ["expected", "departments"], ["unknown"]),
          put_in(row, ["expected", "routes"], ["issue_refund"]),
          put_in(row, ["expected", "requires_human_review"], true)
        ] do
      Fixture.write(path, [invalid])
      assert {:error, {:invalid_row, 1}} = Dataset.load(path)
    end
  end

  test "rejects empty, duplicate-ID, mixed-split and mixed-version datasets", %{tmp_dir: dir} do
    path = Path.join(dir, "bad.jsonl")
    first = Fixture.ticket()
    second = Fixture.ticket("two")

    for {rows, reason} <- [
          {[], :empty_dataset},
          {[first, first], :duplicate_ids},
          {[first, %{second | "split" => "held_out"}], :mixed_splits},
          {[first, %{second | "dataset_version" => "v2"}], :mixed_versions}
        ] do
      Fixture.write(path, rows)
      assert {:error, ^reason} = Dataset.load(path)
    end
  end
end
