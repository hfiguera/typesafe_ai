defmodule TypeSafe.TestServer do
  @moduledoc false
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
  def url(server), do: GenServer.call(server, :url)

  @impl true
  def init(opts) do
    transport = Keyword.get(opts, :transport, :gen_tcp)
    options = [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}]
    options = options ++ Keyword.get(opts, :socket_options, [])
    {:ok, listener} = transport.listen(0, options)
    {:ok, {_address, port}} = sockname(transport, listener)
    counter = :atomics.new(1, [])
    handler = Keyword.fetch!(opts, :handler)
    acceptor = spawn_link(fn -> accept(transport, listener, handler, counter) end)
    {:ok, %{listener: listener, transport: transport, acceptor: acceptor, port: port}}
  end

  @impl true
  def handle_call(:url, _from, state) do
    scheme = if state.transport == :ssl, do: "https", else: "http"
    {:reply, "#{scheme}://localhost:#{state.port}", state}
  end

  @impl true
  def terminate(_reason, state) do
    state.transport.close(state.listener)
    Process.exit(state.acceptor, :shutdown)
  end

  defp sockname(:gen_tcp, listener), do: :inet.sockname(listener)
  defp sockname(:ssl, listener), do: :ssl.sockname(listener)

  defp accept(transport, listener, handler, counter) do
    case accept_socket(transport, listener) do
      {:ok, socket} ->
        worker =
          spawn_link(fn ->
            receive do
              :ready -> serve(transport, socket, handler, counter, "")
            end
          end)

        :ok = transport.controlling_process(socket, worker)
        send(worker, :ready)
        accept(transport, listener, handler, counter)

      {:error, :closed} ->
        :ok

      {:error, _reason} ->
        accept(transport, listener, handler, counter)
    end
  end

  defp accept_socket(:gen_tcp, listener), do: :gen_tcp.accept(listener)

  defp accept_socket(:ssl, listener) do
    with {:ok, socket} <- :ssl.transport_accept(listener), do: :ssl.handshake(socket, 5_000)
  end

  defp serve(transport, socket, {:raw, handler}, _counter, _buffer),
    do: handler.(transport, socket)

  defp serve(transport, socket, handler, counter, buffer) do
    case request(transport, socket, buffer) do
      {:ok, request, remaining} ->
        index = :atomics.add_get(counter, 1, 1)

        action =
          handler.(Map.merge(request, %{socket: socket, transport: transport, index: index}))

        respond(transport, socket, action)
        serve(transport, socket, handler, counter, remaining)

      {:error, _reason} ->
        transport.close(socket)
    end
  end

  defp request(transport, socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [head, rest] ->
        [line | header_lines] = String.split(head, "\r\n")

        headers =
          Map.new(header_lines, fn line ->
            [name, value] = String.split(line, ":", parts: 2)
            {String.downcase(name), String.trim(value)}
          end)

        size = String.to_integer(Map.get(headers, "content-length", "0"))

        with {:ok, body, remaining} <- body(transport, socket, rest, size) do
          {:ok, %{line: line, headers: headers, body: body}, remaining}
        end

      [_partial] ->
        with {:ok, chunk} <- transport.recv(socket, 0, 5_000),
             do: request(transport, socket, buffer <> chunk)
    end
  end

  defp body(_transport, _socket, buffer, size) when byte_size(buffer) >= size,
    do: {:ok, binary_part(buffer, 0, size), binary_part(buffer, size, byte_size(buffer) - size)}

  defp body(transport, socket, buffer, size) do
    with {:ok, chunk} <- transport.recv(socket, 0, 5_000),
         do: body(transport, socket, buffer <> chunk, size)
  end

  defp respond(transport, socket, {:reply, status, body, headers}) do
    header_lines = Enum.map(headers, fn {key, value} -> [key, ": ", value, "\r\n"] end)

    transport.send(socket, [
      "HTTP/1.1 ",
      Integer.to_string(status),
      " Response\r\n",
      "content-length: ",
      Integer.to_string(IO.iodata_length(body)),
      "\r\n",
      header_lines,
      "\r\n",
      body
    ])
  end

  defp respond(transport, socket, {:raw, data}), do: transport.send(socket, data)
  defp respond(transport, socket, :close), do: transport.close(socket)

  def success(value \\ 0.9) do
    JSON.encode!(%{
      model: "test-model",
      answers: %{check: %{type: "noul", noul: value}},
      usage: %{input_tokens: 12, output_tokens: 2}
    })
  end
end
