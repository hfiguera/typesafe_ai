defmodule SupportTriage.WorkflowTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
  alias SupportTriage.{Agent, Batch, CLI, Fixture, Samples}
  alias TypeSafe.{Client, TestServer}

  defp client(handler) do
    server = start_supervised!({TestServer, handler: handler})
    start_supervised!({Client, api_key: "offline-test-key", base_url: TestServer.url(server)})
  end

  test "Jido action batches all questions and reevaluates accumulated context" do
    owner = self()

    client =
      client(fn request ->
        send(owner, {:request, JSON.decode!(request.body)})

        answers =
          if request.index == 1, do: %{}, else: %{"blocking_outage" => 0.95, "urgency" => 3.0}

        {:reply, 200, Fixture.body(answers), []}
      end)

    sample = Samples.fetch("duplicate")
    initial = Agent.new()
    assert {:ok, first} = Agent.submit(initial, sample.message, client: client)
    assert {:ok, second} = Agent.submit(first, sample.follow_up, client: client)
    assert initial.state.history == []
    assert first.state.messages == [sample.message]
    assert second.state.messages == [sample.message, sample.follow_up]

    assert Enum.map(second.state.history, & &1.decision.action) == [
             "refund_review",
             "incident_review"
           ]

    assert_receive {:request, one}
    assert_receive {:request, two}
    assert map_size(one["questions"]) == 11
    assert two["state"]["customer_messages"] == second.state.messages
    assert one["questions"] == two["questions"]
  end

  test "a failed revision keeps history and customer information without reusing a stale decision" do
    client =
      client(fn request ->
        if request.index == 1,
          do: {:reply, 200, Fixture.body(), []},
          else: {:reply, 401, "private-body", []}
      end)

    {:ok, first} = Agent.submit(Agent.new(), "Original", client: client)
    {:ok, second} = Agent.submit(first, "Update", client: client)
    [good, failed] = second.state.history
    assert good.decision.action == "refund_review"
    assert failed.decision == nil
    assert {:error, %TypeSafe.Error{status: 401}} = failed.result
    assert second.state.messages == ["Original", "Update"]
    refute inspect(second) =~ "private-body"
    refute inspect(second) =~ "offline-test-key"
  end

  test "the Jido action does not add retries on top of the SDK" do
    owner = self()

    client =
      client(fn request ->
        send(owner, {:attempt, request.index})
        {:reply, 429, "{}", [{"retry-after", "0"}]}
      end)

    {:ok, agent} = Agent.submit(Agent.new(), "Hello", client: client)
    assert {:error, %TypeSafe.Error{status: 429}} = List.last(agent.state.history).result
    assert_receive {:attempt, 1}
    refute_receive {:attempt, 2}
  end

  test "TypeSafe deadline propagates to a failed agent revision" do
    client =
      client(fn _request ->
        Process.sleep(100)
        {:reply, 200, Fixture.body(), []}
      end)

    {:ok, agent} = Agent.submit(Agent.new(), "Hello", client: client, timeout: 20)
    assert {:error, %TypeSafe.Error{kind: :timeout}} = List.last(agent.state.history).result
  end

  test "interactive menu supports details, follow-up, history, new ticket, and quitting" do
    client = client(fn _request -> {:reply, 200, Fixture.body(), []} end)

    output =
      capture_io("1\n2\n1\nMore information\n3\n4\n0\n", fn ->
        assert :ok = CLI.run([], client: client)
      end)

    assert output =~ "Billing → refund review"
    assert output =~ "refund_reason: duplicate"
    assert output =~ "Changes since revision 1"
    assert output =~ "Revision 2: More information"
    refute output =~ "offline-test-key"
  end

  test "custom text, empty input, invalid menus, and EOF are handled without losing the session" do
    client = client(fn _request -> {:reply, 200, Fixture.body(), []} end)

    output =
      capture_io("invalid\n5\n\n1\nOlá customer\n", fn ->
        assert :ok = CLI.run([], client: client)
      end)

    assert output =~ "Choose a number"
    assert output =~ "empty_message"
    assert output =~ "Olá customer"
    assert {:error, :empty_message} = Agent.submit(Agent.new(), " \n ", client: client)
  end

  test "batch evaluates all samples through the shared client and reports usage" do
    client = client(fn _request -> {:reply, 200, Fixture.body(), []} end)
    results = Batch.run(Samples.all(), client: client)
    assert [_, _, _, _] = results
    output = capture_io(fn -> assert :ok = Batch.report(results) end)
    assert output =~ "Successful evaluations: 4/4"
    assert output =~ "Expected department matches: 1/4"
    assert output =~ "480 in / 120 out"
  end

  test "scripted sample with follow-up returns failure when its final evaluation fails" do
    client = client(fn _request -> {:reply, 401, "{}", []} end)

    output =
      capture_io(fn ->
        assert {:error, :evaluation_failed} =
                 CLI.run(["--sample", "duplicate", "--follow-up"], client: client)
      end)

    assert output =~ "HTTP 401"
    assert output =~ "No new routing decision"
  end

  test "invalid flags and help do not require credentials or contact the API" do
    for args <- [
          ["--unknown"],
          ["--confidence", "2.0"],
          ["--batch", "--sample", "sales"],
          ["--sample", "unknown"],
          ["--follow-up"]
        ] do
      capture_io(fn -> assert {:error, :invalid_arguments} = CLI.run(args) end)
    end

    assert capture_io(fn -> assert :ok = CLI.run(["--help"]) end) =~ "TYPESAFE_API_KEY"

    assert capture_io(fn -> assert {:error, :missing_key} = CLI.run([], client: :absent) end) =~
             "No other API key"
  end
end
