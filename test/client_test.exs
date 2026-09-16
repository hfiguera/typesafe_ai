defmodule TypeSafe.ClientTest do
  use ExUnit.Case, async: true
  alias TypeSafe.{Client, Error, TestServer}

  defp start_client(handler, opts \\ []) do
    server = start_supervised!({TestServer, handler: handler})
    config = [api_key: "test-secret", base_url: TestServer.url(server), protocols: [:http1]]
    start_supervised!({Client, Keyword.merge(config, opts)})
  end

  defp evaluate(client, opts \\ []) do
    TypeSafe.system_one(
      client,
      Keyword.merge([state: "a message", questions: %{"check" => TypeSafe.noul("True?")}], opts)
    )
  end

  test "sends authenticated requests and reuses one connection" do
    owner = self()

    client =
      start_client(fn request ->
        send(owner, {:request, request})
        {:reply, 200, TestServer.success(), []}
      end)

    assert {:ok, first} = evaluate(client)
    assert first.answers["check"].noul == 0.9
    assert {:ok, _} = evaluate(client, model: "other")
    assert_receive {:request, one}
    assert_receive {:request, two}
    assert one.socket == two.socket
    assert one.headers["authorization"] == "Bearer test-secret"
    assert one.line == "POST /v1/systemone HTTP/1.1"
    assert JSON.decode!(two.body)["model"] == "other"
    refute inspect(:sys.get_status(client)) =~ "test-secret"
  end

  test "assembles chunked responses" do
    client =
      start_client(fn _request ->
        body = TestServer.success()

        {:raw,
         [
           "HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\n\r\n",
           Integer.to_string(byte_size(body), 16),
           "\r\n",
           body,
           "\r\n0\r\n\r\n"
         ]}
      end)

    assert {:ok, _} = evaluate(client)
  end

  test "retries explicit overload responses then succeeds" do
    owner = self()

    client =
      start_client(fn request ->
        send(owner, {:attempt, request.index})

        if request.index < 3,
          do: {:reply, 429, "{}", [{"retry-after", "0"}]},
          else: {:reply, 200, TestServer.success(), []}
      end)

    assert {:ok, _} = evaluate(client)
    for index <- 1..3, do: assert_receive({:attempt, ^index})
  end

  test "does not retry permanent HTTP errors and does not echo their bodies" do
    client = start_client(fn _request -> {:reply, 401, "test-secret", []} end)
    assert {:error, %Error{kind: :http, status: 401} = error} = evaluate(client)
    refute inspect(error) =~ "test-secret"
  end

  test "retry wait cannot extend the overall deadline" do
    client = start_client(fn _request -> {:reply, 529, "{}", [{"retry-after", "10"}]} end)
    prioritize_response(client)

    assert {:error, %Error{kind: :timeout, message: "Retry would exceed request deadline"}} =
             evaluate(client, timeout: 5_000)

    refute_received :response_priority_failed
  end

  for size <- [8, 40_000] do
    test "accepts an immediate HTTP/1 response with #{size} bytes of state" do
      owner = self()

      client =
        start_client(fn request ->
          send(owner, {:request, request})
          {:reply, 200, TestServer.success(), []}
        end)

      prioritize_response(client)
      state = String.duplicate("x", unquote(size))
      assert {:ok, _response} = evaluate(client, state: state)
      assert {:ok, _response} = evaluate(client, state: state)
      assert_receive {:request, first}
      assert_receive {:request, second}
      assert first.socket == second.socket
      assert JSON.decode!(first.body)["state"] == state
      refute_received :response_priority_failed
    end
  end

  test "bounds the queue and expires queued requests independently" do
    owner = self()

    client =
      start_client(
        fn request ->
          send(owner, {:arrived, request.index, self()})

          receive do
            :continue -> {:reply, 200, TestServer.success(), []}
          end
        end,
        max_queue: 1
      )

    task = Task.async(fn -> evaluate(client) end)
    assert_receive {:arrived, 1, worker}
    queued = Task.async(fn -> evaluate(client, timeout: 100) end)
    wait_pending(client, 2)
    assert {:error, %Error{kind: :overloaded}} = evaluate(client)
    assert {:error, %Error{kind: :timeout}} = Task.await(queued)
    send(worker, :continue)
    assert {:ok, _} = Task.await(task)
    assert :sys.get_state(client).requests == %{}
  end

  test "in-flight deadline closes HTTP/1 and a later request reconnects" do
    client =
      start_client(fn request ->
        if request.index == 1, do: Process.sleep(150)
        {:reply, 200, TestServer.success(), []}
      end)

    assert {:error, %Error{kind: :timeout}} = evaluate(client, timeout: 40)
    assert {:ok, _} = evaluate(client)
  end

  test "ambiguous failures are not replayed by default" do
    client = start_client(fn _request -> :close end)
    assert {:error, %Error{kind: :transport}} = evaluate(client)
    assert :sys.get_state(client).requests == %{}
  end

  test "explicit transport retry permits reconnecting and replaying" do
    client =
      start_client(
        fn request ->
          if request.index == 1, do: :close, else: {:reply, 200, TestServer.success(), []}
        end,
        retry: [retry_transport: true, base_delay: 0]
      )

    assert {:ok, _} = evaluate(client)
  end

  test "caller termination releases the in-flight slot" do
    owner = self()

    client =
      start_client(fn request ->
        if request.index == 1 do
          send(owner, :arrived)
          Process.sleep(150)
        end

        {:reply, 200, TestServer.success(), []}
      end)

    caller = spawn(fn -> evaluate(client) end)
    assert_receive :arrived
    Process.exit(caller, :kill)
    wait_pending(client, 0)
    assert {:ok, _} = evaluate(client)
  end

  test "limits response bytes" do
    client =
      start_client(fn _request -> {:reply, 200, String.duplicate("x", 100), []} end,
        max_response_bytes: 20
      )

    assert {:error, %Error{kind: :invalid_response}} = evaluate(client)
    assert Process.alive?(client)
  end

  test "invalid client configuration is redacted" do
    for opts <- [
          [],
          [api_key: "secret\nvalue"],
          [api_key: "secret", timeout: -1],
          [api_key: "secret", model: <<255>>],
          [api_key: "secret", base_url: "https://host:invalid"],
          [api_key: "secret", base_url: "https://secret@host"]
        ] do
      assert {:error, %Error{kind: :configuration} = error} = Client.start_link(opts)
      refute inspect(error) =~ "secret"
    end
  end

  test "exhausts bounded retries and permits a per-request policy override" do
    owner = self()

    client =
      start_client(fn request ->
        send(owner, {:attempt, request.index})
        {:reply, 429, "{}", [{"retry-after", "0"}]}
      end)

    assert {:error, %Error{kind: :http, status: 429}} = evaluate(client)
    for index <- 1..3, do: assert_receive({:attempt, ^index})

    assert {:error, %Error{kind: :http, status: 429}} =
             evaluate(client, retry: [max_attempts: 1])

    assert_receive {:attempt, 4}
    refute_receive {:attempt, 5}
  end

  test "invalid responses release capacity and leave a healthy connection reusable" do
    client =
      start_client(fn request ->
        body = if request.index == 1, do: "not JSON", else: TestServer.success()
        {:reply, 200, body, []}
      end)

    assert {:error, %Error{kind: :invalid_response}} = evaluate(client)
    assert {:ok, _} = evaluate(client)
  end

  test "caller death cancels a retry timer and prevents replay" do
    client =
      start_client(fn _request ->
        {:reply, 429, "{}", [{"retry-after", "1"}]}
      end)

    caller = spawn(fn -> evaluate(client) end)
    timer = wait_retry_timer(client)
    Process.exit(caller, :kill)
    wait_pending(client, 0)
    assert Process.read_timer(timer) == false
  end

  test "stopping a client replies to waiting callers and cancels timers" do
    owner = self()

    client =
      start_client(fn _request ->
        send(owner, :arrived)
        Process.sleep(:infinity)
      end)

    task = Task.async(fn -> evaluate(client) end)
    assert_receive :arrived
    [request] = Map.values(:sys.get_state(client).requests)
    GenServer.stop(client)
    assert {:error, %Error{kind: :unavailable}} = Task.await(task)
    assert Process.read_timer(request.timer) == false
  end

  # Force a valid scheduling order: a response to the final body bytes arrives
  # before a queued EOF continuation. No sleeps or production hooks are needed.
  defp prioritize_response(client) do
    :ok = :sys.install(client, {&prioritize_response/3, self()})
  end

  defp prioritize_response(owner, {:noreply, %{conn: %Mint.HTTP1{}, requests: requests}}, _name) do
    case Enum.find(requests, fn {_id, request} -> request.upload == "" end) do
      {id, _request} -> reorder_upload(id, owner)
      nil -> :ok
    end

    owner
  end

  defp prioritize_response(owner, _event, _name), do: owner

  defp reorder_upload(id, owner) do
    receive do
      {:upload, ^id} = upload ->
        receive_response(owner)
        send(self(), upload)
    after
      2_000 -> send(owner, :response_priority_failed)
    end
  end

  defp receive_response(owner) do
    receive do
      {:tcp, _socket, _data} = response -> send(self(), response)
    after
      2_000 -> send(owner, :response_priority_failed)
    end
  end

  defp wait_retry_timer(client, attempts \\ 100)
  defp wait_retry_timer(_client, 0), do: flunk("request did not enter retry wait")

  defp wait_retry_timer(client, attempts) do
    case Map.values(:sys.get_state(client).requests) do
      [%{retry_timer: timer}] when is_reference(timer) ->
        timer

      _other ->
        Process.sleep(5)
        wait_retry_timer(client, attempts - 1)
    end
  end

  defp wait_pending(client, expected, attempts \\ 100)
  defp wait_pending(_client, _expected, 0), do: flunk("pending requests did not settle")

  defp wait_pending(client, expected, attempts) do
    if map_size(:sys.get_state(client).requests) != expected do
      Process.sleep(5)
      wait_pending(client, expected, attempts - 1)
    end
  end
end
