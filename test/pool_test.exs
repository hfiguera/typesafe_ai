defmodule TypeSafe.PoolTest do
  use ExUnit.Case, async: false

  alias TypeSafe.{Client, Error, TestServer}

  defp start_pool(opts \\ []) do
    owner = self()

    server =
      start_supervised!(
        {TestServer,
         handler: fn request ->
           send(owner, {:request, self(), request})

           receive do
             :respond -> {:reply, 200, TestServer.success(), []}
             :overload -> {:reply, 429, "{}", [{"retry-after", "0"}]}
             :disconnect -> :close
           end
         end}
      )

    options = [
      api_key: "pool-secret",
      base_url: TestServer.url(server),
      pool_size: 2,
      protocols: [:http1],
      max_queue: 0
    ]

    start_supervised!({Client, Keyword.merge(options, opts)})
  end

  defp evaluate(client, opts \\ []) do
    TypeSafe.system_one(
      client,
      Keyword.merge([state: "hello", questions: %{"check" => TypeSafe.noul("True?")}], opts)
    )
  end

  defp workers(pool) do
    pool |> Supervisor.which_children() |> Enum.map(&elem(&1, 1))
  end

  test "one named client uses separate connections and retains bounded admission" do
    pool = start_pool(name: __MODULE__, model: "pool-model")
    first = Task.async(fn -> evaluate(__MODULE__, model: "override") end)
    assert_receive {:request, worker1, request1}, 2_000
    second = Task.async(fn -> evaluate(pool) end)
    assert_receive {:request, worker2, request2}, 2_000
    assert request1.socket != request2.socket
    assert JSON.decode!(request1.body)["model"] == "override"
    assert JSON.decode!(request2.body)["model"] == "pool-model"
    assert {:error, %Error{kind: :overloaded}} = evaluate(pool)
    refute inspect(:sys.get_status(pool)) =~ "pool-secret"
    send(worker1, :respond)
    send(worker2, :respond)
    assert {:ok, _} = Task.await(first)
    assert {:ok, _} = Task.await(second)
  end

  test "a rejected request can use another connection without replaying accepted work" do
    pool = start_pool()
    blocked = Task.async(fn -> evaluate(pool) end)
    assert_receive {:request, worker1, _}, 2_000
    available = Task.async(fn -> evaluate(pool) end)
    assert_receive {:request, worker2, _}, 2_000
    send(worker2, :respond)
    assert {:ok, _} = Task.await(available)

    # Round robin selects the still-busy first worker, then tries the free one.
    next = Task.async(fn -> evaluate(pool) end)
    assert_receive {:request, ^worker2, _}, 2_000
    send(worker2, :disconnect)
    assert {:error, %Error{kind: :transport}} = Task.await(next)
    refute_receive {:request, _, _}
    send(worker1, :respond)
    assert {:ok, _} = Task.await(blocked)
  end

  test "worker crashes are isolated and supervision replaces the connection owner" do
    pool = start_pool()
    blocked = Task.async(fn -> evaluate(pool) end)
    assert_receive {:request, _server_worker, _}, 2_000
    [{worker, _}] = Registry.lookup(TypeSafe.PoolRegistry, {pool, 0})
    survivor = workers(pool) -- [worker]
    Process.exit(worker, :kill)
    assert {:error, %Error{kind: :unavailable}} = Task.await(blocked)
    replacement = wait_replacement(pool, worker)
    assert Enum.all?(survivor, &Process.alive?/1)
    assert [_one, _two] = replacement

    for _ <- 1..2 do
      task = Task.async(fn -> evaluate(pool) end)
      assert_receive {:request, server_worker, _}, 2_000
      send(server_worker, :respond)
      assert {:ok, _} = Task.await(task)
    end
  end

  test "missing routing during worker replacement cannot send calls to the supervisor" do
    pool = start_pool()
    :ok = Supervisor.terminate_child(pool, 0)
    assert {:error, %Error{kind: :unavailable}} = evaluate(pool)
    assert Process.alive?(pool)
    assert {:ok, _worker} = Supervisor.restart_child(pool, 0)
    task = Task.async(fn -> evaluate(pool) end)
    assert_receive {:request, server_worker, _}, 2_000
    send(server_worker, :respond)
    assert {:ok, _} = Task.await(task)
  end

  @tag capture_log: true
  test "registry recovery restores routing without retaining stale worker PIDs" do
    pool = start_pool(name: __MODULE__)
    original_workers = workers(pool)
    registry = Process.whereis(TypeSafe.PoolRegistry)
    [{_id, partition, _type, _modules}] = Supervisor.which_children(registry)
    Process.exit(partition, :kill)
    wait_registry(pool, original_workers)
    task = Task.async(fn -> evaluate(__MODULE__) end)
    assert_receive {:request, server_worker, _}, 2_000
    send(server_worker, :respond)
    assert {:ok, _} = Task.await(task)
  end

  test "stopping a pool stops every worker and releases waiting callers" do
    pool = start_pool()
    pids = workers(pool)
    monitors = Enum.map(pids, &Process.monitor/1)
    task = Task.async(fn -> evaluate(pool) end)
    assert_receive {:request, _, _}, 2_000
    Supervisor.stop(pool)
    assert {:error, %Error{kind: :unavailable}} = Task.await(task)
    for monitor <- monitors, do: assert_receive({:DOWN, ^monitor, :process, _, _})
  end

  test "queued deadlines and caller cancellation release each worker's capacity" do
    pool = start_pool(max_queue: 1)
    callers = for _ <- 1..2, do: spawn(fn -> evaluate(pool) end)
    for _ <- 1..2, do: assert_receive({:request, _, _}, 2_000)
    assert {:error, %Error{kind: :timeout}} = evaluate(pool, timeout: 30)
    Enum.each(callers, &Process.exit(&1, :kill))
    Enum.each(workers(pool), &wait_empty/1)
    task = Task.async(fn -> evaluate(pool) end)
    assert_receive {:request, server_worker, _}, 2_000
    send(server_worker, :respond)
    assert {:ok, _} = Task.await(task)
  end

  test "retry stays on the chosen worker and respects the attempt limit" do
    pool = start_pool()
    task = Task.async(fn -> evaluate(pool, retry: [max_attempts: 2]) end)
    assert_receive {:request, server_worker, first}, 2_000
    send(server_worker, :overload)
    assert_receive {:request, ^server_worker, second}, 2_000
    assert first.socket == second.socket
    send(server_worker, :overload)
    assert {:error, %Error{kind: :http, status: 429}} = Task.await(task)
    refute_receive {:request, _, _}
  end

  test "rejects invalid pool sizes without exposing credentials" do
    for size <- [0, -1, 1.5, nil, "4"] do
      assert {:error, %Error{kind: :configuration} = error} =
               Client.start_link(api_key: "pool-secret", pool_size: size)

      refute inspect(error) =~ "pool-secret"
    end
  end

  defp wait_registry(pool, original_workers, attempts \\ 100)
  defp wait_registry(_pool, _original, 0), do: flunk("registry did not recover")

  defp wait_registry(pool, original, attempts) do
    if routing_ready?(pool, original) do
      :ok
    else
      Process.sleep(5)
      wait_registry(pool, original, attempts - 1)
    end
  end

  defp routing_ready?(pool, original) do
    Enum.all?(original, &(not Process.alive?(&1))) and
      Registry.lookup(TypeSafe.PoolRegistry, pool) != []
  rescue
    ArgumentError -> false
  end

  defp wait_replacement(pool, original, attempts \\ 100)
  defp wait_replacement(_pool, _original, 0), do: flunk("worker did not restart")

  defp wait_replacement(pool, original, attempts) do
    current = workers(pool)

    if original in current or :restarting in current do
      Process.sleep(5)
      wait_replacement(pool, original, attempts - 1)
    else
      current
    end
  end

  defp wait_empty(worker, attempts \\ 100)
  defp wait_empty(_worker, 0), do: flunk("worker retained cancelled work")

  defp wait_empty(worker, attempts) do
    if map_size(:sys.get_state(worker).requests) > 0 do
      Process.sleep(5)
      wait_empty(worker, attempts - 1)
    end
  end
end
