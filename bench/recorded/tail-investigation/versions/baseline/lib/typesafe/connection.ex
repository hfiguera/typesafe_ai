defmodule TypeSafe.Connection do
  @moduledoc false
  alias TypeSafe.Config

  @spec start(struct(), pid()) :: {pid(), reference()}
  def start(config, owner) do
    spawn_monitor(fn ->
      result = connect(config, owner)
      send(owner, {:typesafe_connected, self(), result})
    end)
  end

  defp connect(config, owner) do
    scheme = if config.uri.scheme == "https", do: :https, else: :http

    with {:ok, conn} <-
           Mint.HTTP.connect(
             scheme,
             config.uri.host,
             config.uri.port,
             Config.connect_options(config)
           ),
         {:ok, conn} <- transfer(conn, owner) do
      {:ok, conn}
    else
      {:error, _reason} -> {:error, :connect_failed}
    end
  rescue
    ArgumentError -> {:error, :connect_failed}
    ErlangError -> {:error, :connect_failed}
  end

  defp transfer(conn, owner) do
    case Mint.HTTP.controlling_process(conn, owner) do
      {:ok, conn} ->
        {:ok, conn}

      {:error, reason} ->
        Mint.HTTP.close(conn)
        {:error, reason}
    end
  end
end
