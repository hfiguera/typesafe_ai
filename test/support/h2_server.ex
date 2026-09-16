defmodule TypeSafe.H2Server do
  @moduledoc false
  import Bitwise

  def serve(:ssl, socket, owner) do
    {:ok, "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"} = :ssl.recv(socket, 24, 5_000)
    send_frame(socket, 4, 0, 0, <<3::16, 2::32, 4::16, 1_024::32>>)
    :ok = :ssl.setopts(socket, active: true)
    loop(%{socket: socket, owner: owner, buffer: "", decoder: HPAX.new(4_096), streams: %{}})
  end

  defp loop(state) do
    receive do
      {:ssl, _socket, bytes} ->
        state |> Map.update!(:buffer, &(&1 <> bytes)) |> frames() |> loop()

      {:respond, stream, body} ->
        {headers, _table} = HPAX.encode(:no_store, [{":status", "200"}], HPAX.new(4_096))
        send_frame(state.socket, 1, 4, stream, headers)
        send_frame(state.socket, 0, 1, stream, body)
        loop(state)

      {:reset, stream} ->
        send_frame(state.socket, 3, 0, stream, <<2::32>>)
        loop(state)

      {:goaway, last_stream} ->
        send_frame(state.socket, 7, 0, 0, <<0::1, last_stream::31, 0::32>>)
        loop(state)

      {:ssl_closed, _socket} ->
        :ok

      {:ssl_error, _socket, _reason} ->
        :ok
    end
  end

  defp frames(
         %{buffer: <<size::24, type, flags, _reserved::1, stream::31, rest::binary>>} = state
       )
       when byte_size(rest) >= size do
    payload = binary_part(rest, 0, size)
    state = %{state | buffer: binary_part(rest, size, byte_size(rest) - size)}
    state |> frame(type, flags, stream, payload) |> frames()
  end

  defp frames(state), do: state

  defp frame(state, 4, 0, 0, _settings) do
    send_frame(state.socket, 4, 1, 0, "")
    state
  end

  defp frame(state, 1, _flags, stream, payload) do
    {:ok, headers, decoder} = HPAX.decode(payload, state.decoder)

    %{
      state
      | decoder: decoder,
        streams: Map.put(state.streams, stream, %{headers: headers, chunks: []})
    }
  end

  defp frame(state, 0, flags, stream, payload) do
    state = update_in(state.streams[stream].chunks, &[payload | &1])

    if byte_size(payload) > 0 do
      send_frame(state.socket, 8, 0, 0, <<byte_size(payload)::32>>)
      send_frame(state.socket, 8, 0, stream, <<byte_size(payload)::32>>)
    end

    if band(flags, 1) == 1 do
      request = state.streams[stream]
      body = request.chunks |> Enum.reverse() |> IO.iodata_to_binary()
      send(state.owner, {:h2_request, self(), stream, request.headers, body})
      %{state | streams: Map.delete(state.streams, stream)}
    else
      state
    end
  end

  defp frame(state, 3, _flags, stream, _payload) do
    send(state.owner, {:h2_cancel, stream})
    %{state | streams: Map.delete(state.streams, stream)}
  end

  defp frame(state, _type, _flags, _stream, _payload), do: state

  defp send_frame(socket, type, flags, stream, body) do
    :ssl.send(socket, [<<IO.iodata_length(body)::24, type, flags, 0::1, stream::31>>, body])
  end
end
