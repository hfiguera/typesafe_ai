defmodule SupportTriage.Evaluation.WorkflowTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
  alias SupportTriage.Evaluation.{CLI, Dataset, Report, Runner}
  alias SupportTriage.EvaluationFixture
  alias SupportTriage.Fixture
  alias TypeSafe.{Client, TestServer}
  @moduletag :tmp_dir

  defp client(handler) do
    server = start_supervised!({TestServer, handler: handler})
    start_supervised!({Client, api_key: "offline-test-key", base_url: TestServer.url(server)})
  end

  test "messages accumulate through Jido while expected labels never enter model input" do
    owner = self()

    client =
      client(fn request ->
        send(owner, {:wire, JSON.decode!(request.body)})
        {:reply, 200, Fixture.body(), []}
      end)

    ticket = %{EvaluationFixture.ticket() | "messages" => ["First", "Update"]}
    assert [result] = Runner.run([ticket], client: client, model: "requested-model")
    assert result.error == nil
    assert [_, _] = result.history
    assert_receive {:wire, first}
    assert_receive {:wire, second}
    assert first["state"] == %{"customer_messages" => ["First"]}
    assert second["state"] == %{"customer_messages" => ["First", "Update"]}
    assert second["model"] == "requested-model"
    refute Map.has_key?(second, "expected")
  end

  test "CLI saves complete metadata and typed answers without input text or credentials", %{
    tmp_dir: dir
  } do
    client = client(fn _request -> {:reply, 200, Fixture.body(), []} end)
    path = Path.join(dir, "dataset.jsonl")
    output = Path.join(dir, "report.json")
    EvaluationFixture.write(path, [EvaluationFixture.ticket()])

    capture_io(fn ->
      assert :ok =
               CLI.run(
                 [
                   "--dataset",
                   path,
                   "--output",
                   output,
                   "--confidence",
                   "0.95",
                   "--model",
                   "specific-model"
                 ],
                 client: client
               )
    end)

    bytes = File.read!(output)
    report = JSON.decode!(bytes)
    assert report["policy"]["confidence"] == 0.95
    assert report["summary"]["department_correct"]["count"] == 1
    assert report["summary"]["route_correct"]["count"] == 0
    assert report["requested_model"] == "specific-model"
    assert report["actual_models"] == ["offline-fixture"]
    assert byte_size(report["questions_sha256"]) == 64
    assert byte_size(report["policy_sha256"]) == 64
    assert byte_size(report["dataset"]["sha256"]) == 64
    assert report["selected_ids"] == ["one"]
    [row] = report["cases"]
    [revision] = row["history"]
    assert revision["result"]["answers"]["department"]["type"] == "choice"
    refute bytes =~ "Private customer text"
    refute bytes =~ "offline-test-key"
  end

  test "failure results are saved, count as incorrect, and stop later revisions", %{tmp_dir: dir} do
    owner = self()

    client =
      client(fn request ->
        send(owner, {:request, request.index})
        {:reply, 429, "private-response-body", []}
      end)

    path = Path.join(dir, "dataset.jsonl")
    output = Path.join(dir, "report.json")
    ticket = %{EvaluationFixture.ticket() | "messages" => ["First", "Update"]}
    EvaluationFixture.write(path, [ticket])

    capture_io(fn ->
      assert {:error, :evaluation_failed} =
               CLI.run(["--dataset", path, "--output", output], client: client)
    end)

    report = output |> File.read!() |> JSON.decode!()
    assert report["summary"]["failures"] == 1
    assert report["summary"]["route_correct"]["fraction"] == 0.0
    assert report["summary"]["requests_recorded"] == 1
    assert_receive {:request, 1}
    refute_receive {:request, 2}
    refute File.read!(output) =~ "private-response-body"
  end

  test "existing output is rejected before requests and exclusive saving never overwrites", %{
    tmp_dir: dir
  } do
    owner = self()

    client =
      client(fn _request ->
        send(owner, :unexpected)
        {:reply, 200, Fixture.body(), []}
      end)

    path = Path.join(dir, "dataset.jsonl")
    output = Path.join(dir, "report.json")
    EvaluationFixture.write(path, [EvaluationFixture.ticket()])
    File.write!(output, "keep me")

    assert {:error, :output_exists} =
             CLI.run(["--dataset", path, "--output", output], client: client)

    assert {:error, :eexist} = Report.save(output, %{})
    assert File.read!(output) == "keep me"
    refute_receive :unexpected
  end

  test "invalid arguments and malformed data fail before evaluation", %{tmp_dir: dir} do
    for args <- [
          ["--confidence", "1.1"],
          ["--timeout", "0"],
          ["--limit", "0"],
          ["--concurrency", "5"],
          ["--model", ""],
          ["--unknown"]
        ] do
      capture_io(fn -> assert {:error, :invalid_arguments} = CLI.run(args) end)
    end

    path = Path.join(dir, "bad.jsonl")
    File.write!(path, "bad json")
    assert {:error, {:invalid_json, 1}} = CLI.run(["--dataset", path])
    assert capture_io(fn -> assert :ok = CLI.run(["--help"]) end) =~ "billable"
  end

  test "limits select a reproducible prefix without changing the full dataset fingerprint", %{
    tmp_dir: dir
  } do
    client = client(fn _request -> {:reply, 200, Fixture.body(), []} end)
    path = Path.join(dir, "dataset.jsonl")
    output = Path.join(dir, "report.json")

    EvaluationFixture.write(path, [
      EvaluationFixture.ticket("first"),
      EvaluationFixture.ticket("second")
    ])

    {:ok, dataset} = Dataset.load(path)

    capture_io(fn ->
      assert :ok =
               CLI.run(["--dataset", path, "--output", output, "--limit", "1"], client: client)
    end)

    report = output |> File.read!() |> JSON.decode!()
    assert report["selected_ids"] == ["first"]
    assert report["dataset"]["sha256"] == dataset.sha256
  end
end
