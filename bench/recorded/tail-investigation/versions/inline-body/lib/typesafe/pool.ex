defmodule TypeSafe.Pool do
  @moduledoc false
  use Supervisor

  alias TypeSafe.{Client, Error, Request}

  @spec start_link(struct()) :: Supervisor.on_start()
  def start_link(config) do
    Supervisor.start_link(__MODULE__, config, if(config.name, do: [name: config.name], else: []))
  end

  @impl true
  def init(config) do
    pool = self()
    counter = :atomics.new(1, signed: false)

    children =
      for index <- 0..(config.pool_size - 1) do
        name = {:via, Registry, {TypeSafe.PoolRegistry, {pool, index}}}
        worker = %{config | name: name, pool_size: 1}

        init =
          if index == 0,
            do: {worker, pool, {counter, config.pool_size, config.model}},
            else: worker

        %{
          id: index,
          start: {GenServer, :start_link, [Client, init, [name: name]]}
        }
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  @spec evaluate(GenServer.server(), map()) :: term()
  def evaluate(client, request) do
    pid = GenServer.whereis(client)

    if is_pid(pid) and node(pid) == node() do
      evaluate_local(pid, request)
    else
      {:error, Error.new(:unavailable, "Client is not available on this node")}
    end
  end

  defp evaluate_local(pid, request) do
    case lookup(pid) do
      [{_owner, {counter, size, model}}] ->
        request = Request.encode_body(request, model)
        index = rem(:atomics.add_get(counter, 1, 1) - 1, size)
        dispatch(pid, request, index, size, size)

      [{^pid, {:connection, model}}] ->
        GenServer.call(pid, {:evaluate, Request.encode_body(request, model)}, :infinity)

      [] ->
        {:error, Error.new(:unavailable, "Client routing is unavailable")}
    end
  end

  defp lookup(pid) do
    Registry.lookup(TypeSafe.PoolRegistry, pid)
  rescue
    ArgumentError -> []
  end

  defp dispatch(_pool, _request, _index, _size, 0),
    do: {:error, Error.new(:overloaded, "Client pool is full")}

  defp dispatch(pool, request, index, size, remaining) do
    worker = {:via, Registry, {TypeSafe.PoolRegistry, {pool, index}}}

    case GenServer.call(worker, {:evaluate, request}, :infinity) do
      {:error, %Error{kind: :overloaded}} ->
        # Only rejected work can move to another connection; accepted work may
        # already have reached the service and must retain its retry policy.
        dispatch(pool, request, rem(index + 1, size), size, remaining - 1)

      result ->
        result
    end
  end
end
