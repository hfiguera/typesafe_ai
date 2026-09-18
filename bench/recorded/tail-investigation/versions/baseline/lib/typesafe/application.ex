defmodule TypeSafe.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(
      [{Registry, keys: :unique, name: TypeSafe.PoolRegistry}],
      strategy: :one_for_one,
      name: TypeSafe.Supervisor
    )
  end
end
