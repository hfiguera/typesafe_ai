defmodule TypeSafe.Client do
  @moduledoc """
  Supervised owner of a reusable Mint connection.

  Required: `:api_key`. Optional: `:name`, `:base_url`, `:model`, `:timeout`
  (30,000 ms overall), `:connect_timeout` (5,000 ms), `:max_concurrency` (10),
  `:max_queue` (100), `:max_response_bytes` (8 MiB), `:protocols`
  (`[:http1, :http2]`), `:transport_opts` (CA certificates and TLS versions), and
  `:retry` (`TypeSafe.Retry` or keyword options).

  HTTP/1 runs one request at a time. HTTP/2 multiplexes up to the configured and
  server-advertised limits. Queue and retry waits count toward the deadline.
  Connections are established lazily; starting a client needs no network access.
  """
  use GenServer

  alias TypeSafe.{Config, Connection, Error, Request, Response, Retry}

  @doc "Starts a client linked to the caller."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    with {:ok, config} <- Config.new(opts) do
      GenServer.start_link(__MODULE__, config, if(config.name, do: [name: config.name], else: []))
    end
  end

  @doc false
  @spec evaluate(GenServer.server(), map()) :: {:ok, Response.t()} | {:error, Error.t()}
  def evaluate(client, request) do
    GenServer.call(client, {:evaluate, request}, :infinity)
  catch
    :exit, _reason -> {:error, Error.new(:unavailable, "Client is unavailable")}
  end

  @impl true
  def init(config) do
    {:ok,
     %{config: config, conn: nil, connector: nil, requests: %{}, refs: %{}, queue: :queue.new()}}
  end

  @impl true
  def handle_call({:evaluate, request}, from, state) do
    capacity = limit(state) + state.config.max_queue

    if map_size(state.requests) < capacity do
      {:noreply, state |> enqueue(request, from) |> pump()}
    else
      {:reply, {:error, Error.new(:overloaded, "Client queue is full")}, state}
    end
  end

  @impl true
  def handle_info({:typesafe_connected, pid, result}, %{connector: {pid, monitor}} = state) do
    Process.demonitor(monitor, [:flush])
    state = %{state | connector: nil}

    case activate(result) do
      {:ok, conn} -> {:noreply, pump(%{state | conn: conn})}
      {:error, _reason} -> {:noreply, fail_waiting(state)}
    end
  end

  def handle_info({:typesafe_connected, _pid, {:ok, conn}}, state) do
    Mint.HTTP.close(conn)
    {:noreply, state}
  end

  def handle_info({:typesafe_connected, _pid, _result}, state), do: {:noreply, state}

  def handle_info({:deadline, id}, state) do
    {:noreply,
     state |> abandon(id, {:error, Error.new(:timeout, "Request deadline exceeded")}) |> pump()}
  end

  def handle_info({:retry, id}, state) do
    case state.requests[id] do
      %{phase: :backoff} = request ->
        state = put_in(state.requests[id], %{request | phase: :queued, retry_timer: nil})
        {:noreply, pump(%{state | queue: :queue.in(id, state.queue)})}

      _other ->
        {:noreply, state}
    end
  end

  def handle_info({:upload, id}, state) do
    case state.requests[id] do
      %{phase: :inflight} ->
        state = put_in(state.requests[id].upload_scheduled, false)
        {:noreply, state |> upload(id) |> pump()}

      _other ->
        {:noreply, state}
    end
  end

  def handle_info(
        {:DOWN, monitor, :process, _pid, _reason},
        %{connector: {_worker, monitor}} = state
      ) do
    {:noreply, fail_waiting(%{state | connector: nil})}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    case Enum.find(state.requests, fn {_id, r} -> r.monitor == monitor end) do
      {id, _request} -> {:noreply, state |> abandon(id, :caller_down) |> pump()}
      nil -> {:noreply, state}
    end
  end

  def handle_info(message, %{conn: conn} = state) when not is_nil(conn) do
    case Mint.HTTP.stream(conn, message) do
      :unknown ->
        {:noreply, state}

      {:ok, conn, events} ->
        {:noreply, state |> Map.put(:conn, conn) |> events(events) |> pump()}

      {:error, conn, _reason, events} ->
        {:noreply, state |> Map.put(:conn, conn) |> events(events) |> disconnect() |> pump()}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    close(state.conn)
    stop_connector(state.connector)

    Enum.each(Map.keys(state.requests), fn id ->
      finish(state, id, {:error, Error.new(:unavailable, "Client stopped")})
    end)

    :ok
  end

  @impl true
  def format_status(status) do
    Map.new(status, fn
      {:state, state} ->
        {:state, %{pending: map_size(state.requests), connected: not is_nil(state.conn)}}

      {key, _value} when key in [:message, :log, :reason] ->
        {key, :redacted}

      other ->
        other
    end)
  end

  defp enqueue(state, request, from) do
    id = make_ref()
    deadline = request.started + (request.timeout || state.config.timeout)
    timer = Process.send_after(self(), {:deadline, id}, max(deadline - now(), 0))

    r = %{
      input: request,
      from: from,
      monitor: Process.monitor(elem(from, 0)),
      timer: timer,
      retry_timer: nil,
      deadline: deadline,
      phase: :queued,
      attempt: 0,
      ref: nil,
      status: nil,
      headers: [],
      chunks: [],
      bytes: 0,
      upload: nil,
      upload_scheduled: false,
      retry: request.retry || state.config.retry
    }

    emit(:start, %{system_time: System.system_time()}, %{request_id: id})
    %{state | requests: Map.put(state.requests, id, r), queue: :queue.in(id, state.queue)}
  end

  defp pump(%{requests: requests} = state) when map_size(requests) == 0 do
    stop_connector(state.connector)
    %{state | connector: nil, queue: :queue.new()}
  end

  defp pump(%{conn: nil, connector: nil} = state) do
    if :queue.is_empty(state.queue),
      do: state,
      else: %{state | connector: Connection.start(state.config, self())}
  end

  defp pump(%{conn: nil} = state), do: state

  defp pump(state) do
    cond do
      Mint.HTTP.open?(state.conn, :write) ->
        state |> flush_uploads() |> dispatch()

      Mint.HTTP.open?(state.conn, :read) and map_size(state.refs) > 0 ->
        flush_uploads(state)

      true ->
        state |> disconnect() |> pump()
    end
  end

  defp dispatch(%{conn: nil} = state), do: pump(state)

  defp dispatch(state) do
    if map_size(state.refs) < limit(state) do
      next(state)
    else
      state
    end
  end

  defp next(state) do
    current_time = now()

    case :queue.out(state.queue) do
      {:empty, _queue} ->
        state

      {{:value, id}, queue} ->
        state = %{state | queue: queue}

        case state.requests[id] do
          nil ->
            dispatch(state)

          %{deadline: deadline} when deadline <= current_time ->
            state
            |> finish(id, {:error, Error.new(:timeout, "Request deadline exceeded")})
            |> dispatch()

          request ->
            state |> submit(id, request) |> dispatch()
        end
    end
  end

  defp submit(state, id, request) do
    body = request.input |> Request.body(state.config.model) |> IO.iodata_to_binary()
    path = String.trim_trailing(state.config.uri.path || "", "/") <> "/v1/systemone"

    headers = [
      {"authorization", "Bearer " <> state.config.api_key},
      {"content-type", "application/json"},
      {"accept", "application/json"},
      {"content-length", Integer.to_string(byte_size(body))}
    ]

    request = %{request | attempt: request.attempt + 1, phase: :inflight}
    state = put_in(state.requests[id], request)

    case Mint.HTTP.request(state.conn, "POST", path, headers, :stream) do
      {:ok, conn, ref} ->
        request = %{request | ref: ref, upload: body}

        state = %{
          state
          | conn: conn,
            refs: Map.put(state.refs, ref, id),
            requests: Map.put(state.requests, id, request)
        }

        upload(state, id)

      {:error, conn, _reason} ->
        state |> Map.put(:conn, conn) |> transport_failure(id) |> disconnect()
    end
  end

  defp flush_uploads(state) do
    Enum.reduce(Map.values(state.refs), state, &upload(&2, &1))
  end

  defp upload(%{conn: nil} = state, _id), do: state

  defp upload(state, id) do
    current_time = now()

    case state.requests[id] do
      %{deadline: deadline} when deadline <= current_time ->
        abandon(state, id, {:error, Error.new(:timeout, "Request deadline exceeded")})

      %{upload: body, ref: ref, upload_scheduled: false} when is_binary(body) ->
        window = Mint.HTTP.request_body_window(state.conn, ref)
        size = max(0, min(byte_size(body), min(window, 16_384)))
        send_chunk(state, id, body, size)

      _other ->
        state
    end
  end

  defp send_chunk(state, _id, body, 0) when body != "", do: state

  defp send_chunk(state, id, body, size) do
    chunk = binary_part(body, 0, size)
    rest = binary_part(body, size, byte_size(body) - size)
    data = if body == "", do: :eof, else: chunk

    case Mint.HTTP.stream_request_body(state.conn, state.requests[id].ref, data) do
      {:ok, conn} ->
        state = %{state | conn: conn}
        state = put_in(state.requests[id].upload, if(data == :eof, do: nil, else: rest))

        if data == :eof do
          state
        else
          send(self(), {:upload, id})
          put_in(state.requests[id].upload_scheduled, true)
        end

      {:error, conn, _reason} ->
        state |> Map.put(:conn, conn) |> disconnect()
    end
  end

  defp events(state, events), do: Enum.reduce(events, state, &event/2)

  defp event(event, state) do
    ref = elem(event, 1)

    case state.refs[ref] do
      nil -> state
      id -> response_event(event, id, state)
    end
  end

  defp response_event({:status, _ref, status}, id, state),
    do: put_in(state.requests[id].status, status)

  defp response_event({:headers, _ref, headers}, id, state),
    do: update_in(state.requests[id].headers, &(&1 ++ headers))

  defp response_event({:data, _ref, chunk}, id, state) do
    r = state.requests[id]

    if r.bytes + byte_size(chunk) <= state.config.max_response_bytes do
      put_in(state.requests[id], %{
        r
        | chunks: [chunk | r.chunks],
          bytes: r.bytes + byte_size(chunk)
      })
    else
      abandon(state, id, {:error, Error.new(:invalid_response, "Response exceeds size limit")})
    end
  end

  defp response_event({:done, ref}, id, state) do
    r = state.requests[id]
    state = %{state | refs: Map.delete(state.refs, ref)}
    state = put_in(state.requests[id].ref, nil)

    cond do
      r.deadline <= now() ->
        finish(state, id, {:error, Error.new(:timeout, "Request deadline exceeded")})

      r.status in 200..299 ->
        body = r.chunks |> Enum.reverse() |> IO.iodata_to_binary()
        finish(state, id, Response.decode(body, r.input.schema))

      r.status in r.retry.statuses and r.attempt < r.retry.max_attempts ->
        retry(state, id)

      true ->
        finish(state, id, {:error, Error.new(:http, "TypeSafe returned an HTTP error", r.status)})
    end
  end

  defp response_event({:error, ref, _reason}, id, state) do
    state = %{state | refs: Map.delete(state.refs, ref)}
    state |> put_in([:requests, id, :ref], nil) |> transport_failure(id)
  end

  defp transport_failure(state, id) do
    r = state.requests[id]

    if r.retry.retry_transport and r.attempt < r.retry.max_attempts do
      retry(state, id)
    else
      finish(
        state,
        id,
        {:error, Error.new(:transport, "Connection failed; evaluation may have been processed")}
      )
    end
  end

  defp retry(state, id) do
    r = state.requests[id]
    delay = Retry.delay(r.retry, max(r.attempt, 1), r.headers)

    if now() + delay >= r.deadline do
      finish(state, id, {:error, Error.new(:timeout, "Retry would exceed request deadline")})
    else
      timer = Process.send_after(self(), {:retry, id}, delay)
      emit(:retry, %{delay: delay, attempt: r.attempt}, %{request_id: id, status: r.status})

      put_in(state.requests[id], %{
        r
        | phase: :backoff,
          retry_timer: timer,
          ref: nil,
          upload: nil,
          upload_scheduled: false,
          chunks: [],
          headers: [],
          bytes: 0,
          status: nil
      })
    end
  end

  defp abandon(state, id, result) do
    case state.requests[id] do
      nil ->
        state

      %{ref: nil} ->
        finish(state, id, result)

      %{ref: ref} ->
        state = finish(state, id, result)

        if state.conn && Mint.HTTP.protocol(state.conn) == :http2 do
          cancel_stream(state, ref)
        else
          disconnect(state)
        end
    end
  end

  defp cancel_stream(state, ref) do
    case Mint.HTTP2.cancel_request(state.conn, ref) do
      {:ok, conn} -> %{state | conn: conn}
      {:error, conn, _reason} -> state |> Map.put(:conn, conn) |> disconnect()
    end
  end

  defp finish(state, id, result) do
    {r, requests} = Map.pop(state.requests, id)
    Process.cancel_timer(r.timer)
    cancel_timer(r.retry_timer)
    Process.demonitor(r.monitor, [:flush])
    if result != :caller_down, do: GenServer.reply(r.from, result)

    emit(
      :stop,
      Map.merge(%{duration: now() - r.input.started, attempts: r.attempt}, usage(result)),
      %{request_id: id, outcome: outcome(result)}
    )

    %{
      state
      | requests: requests,
        refs: Map.delete(state.refs, r.ref),
        queue: :queue.filter(&(&1 != id), state.queue)
    }
  end

  defp disconnect(state) do
    close(state.conn)
    ids = Map.values(state.refs)
    state = %{state | conn: nil, refs: %{}}

    Enum.reduce(ids, state, fn id, acc ->
      acc |> put_in([:requests, id, :ref], nil) |> transport_failure(id)
    end)
  end

  defp fail_waiting(state) do
    Enum.reduce(Map.keys(state.requests), state, fn id, acc ->
      finish(acc, id, {:error, Error.new(:transport, "Could not establish connection")})
    end)
  end

  defp activate({:ok, conn}) do
    case Mint.HTTP.set_mode(conn, :active) do
      {:ok, conn} ->
        {:ok, conn}

      {:error, reason} ->
        close(conn)
        {:error, reason}
    end
  end

  defp activate(error), do: error
  defp close(nil), do: :ok
  defp close(conn), do: Mint.HTTP.close(conn)
  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)
  defp stop_connector(nil), do: :ok

  defp stop_connector({pid, monitor}) do
    Process.demonitor(monitor, [:flush])
    Process.exit(pid, :kill)
  end

  defp limit(%{conn: nil}), do: 1

  defp limit(state) do
    case Mint.HTTP.protocol(state.conn) do
      :http1 ->
        1

      :http2 ->
        min(
          state.config.max_concurrency,
          Mint.HTTP2.get_server_setting(state.conn, :max_concurrent_streams)
        )
    end
  end

  defp usage({:ok, response}), do: response.usage
  defp usage(_result), do: %{}
  defp outcome({:ok, _response}), do: :ok
  defp outcome({:error, error}), do: error.kind
  defp outcome(:caller_down), do: :cancelled

  defp emit(event, measurements, metadata),
    do: :telemetry.execute([:typesafe, :request, event], measurements, metadata)

  defp now, do: System.monotonic_time(:millisecond)
end
