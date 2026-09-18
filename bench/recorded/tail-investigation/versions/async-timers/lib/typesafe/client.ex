defmodule TypeSafe.Client do
  @moduledoc """
  A supervised TypeSafe AI client with bounded concurrency and queues.

  Reuses Mint HTTP connections with optional pooling, request deadlines,
  configurable retries, and telemetry.

  Add this module to your application's supervision tree and use
  `TypeSafe.system_one/2` to evaluate state. Connections are opened lazily:
  starting a client validates configuration but does not authenticate with the
  service or require network access.

  ```elixir
  children = [
    {TypeSafe.Client,
     name: MyApp.TypeSafe,
     api_key: System.fetch_env!("TYPESAFE_API_KEY")}
  ]
  ```

  The application retrieves the key. This library does not read environment
  variables or Keychain automatically. Use separate clients for separate keys;
  see the [configuration guide](guides/configuration.md) for multiple child IDs.

  ## Connection lifecycle

  By default the client owns one connection. Set `:pool_size` above one to start
  a supervisor with independent connection workers behind the same client name
  or PID. Requests are distributed round robin, without sending their payloads
  through a central dispatcher. Each worker opens its connection lazily.

  HTTP/1 runs one request at a time per connection. HTTP/2 multiplexes up to the
  configured and server-advertised stream limits on each connection. Each worker
  bounds outstanding network work, including backoff waits, by the current protocol capacity plus `:max_queue`. Before
  negotiation the active capacity is conservatively one. Excess calls return
  `:overloaded` after all workers reject admission. A full worker is skipped;
  accepted work stays with its worker for its entire retry lifecycle. There is
  no global FIFO queue or work stealing between workers.

  Response decoding and validation run in the caller, after the worker releases
  its network slot. The deadline is checked before and after decoding. Bound
  caller concurrency as well as network capacity to control CPU and memory use.

  Queueing, connecting, uploading, receiving, and retry waits share one request
  deadline. Socket sends have a one-second upper timeout; a blocked send or
  process scheduling may delay delivery of the timeout result.

  Caller termination releases pending work. HTTP/1 cancellation closes the
  connection; HTTP/2 cancellation resets the individual stream. Healthy
  connections are reused, and subsequent work reconnects after a disconnect.
  A disconnect may happen after the remote evaluation was processed; see
  `TypeSafe.Retry` before enabling transport replay.

  Tune `:pool_size` and `:max_concurrency` against your workload. More connections
  do not raise the service quota and may increase memory use and queueing. See
  the [performance guide](guides/performance.md) for measurement and tuning.

  Response bodies are buffered up to `:max_response_bytes`. There is no public
  streaming API. Formatted process status is redacted, but privileged BEAM inspection can access actual process memory.
  """
  use GenServer

  alias TypeSafe.{Config, Connection, Error, Pool, Response, Retry}

  # Use fewer upload steps for modest buffered bodies. Larger uploads retain
  # the smaller send budget so other streams can make progress.
  # Mint splits each send into legal protocol frames.
  @buffered_upload_bytes 131_072
  @buffered_upload_chunk_bytes 65_536
  @upload_chunk_bytes 16_384

  @doc """
  Starts a client linked to the caller, usually through a supervisor.

  ## Options

  | Option | Default | Description |
  | --- | --- | --- |
  | `:api_key` | Required | Non-empty binary; CR, LF, and NUL are rejected |
  | `:name` | Unnamed | A `GenServer` registration name |
  | `:base_url` | `"https://api.typesafe.ai"` | HTTP(S) endpoint root, optionally with a path prefix |
  | `:model` | `"jev-latest"` | Non-empty UTF-8 model identifier |
  | `:timeout` | `30_000` | Positive overall deadline, in milliseconds |
  | `:connect_timeout` | `5_000` | Positive connection timeout, in milliseconds |
  | `:pool_size` | `1` | Positive number of independent connection workers |
  | `:max_concurrency` | `10` | Positive maximum number of HTTP/2 streams per connection |
  | `:max_queue` | `100` | Non-negative number of additional outstanding slots per connection |
  | `:max_response_bytes` | `8_388_608` | Positive response body limit in bytes |
  | `:protocols` | `[:http1, :http2]` | Either or both protocols, without duplicates |
  | `:transport_opts` | `[]` | TLS options: `:cacerts`, `:cacertfile`, `:versions` |
  | `:retry` | `[]` | Keyword options or a `TypeSafe.Retry` struct |

  Unknown options are rejected. `:base_url` must not contain credentials, a query,
  or a fragment. Requests append `/v1/systemone` to its optional path prefix.
  HTTPS verifies the certificate and hostname using OTP's CA store, or the
  supplied certificates. Verification cannot be disabled through these options.

  Returns `{:ok, pid}` on startup. Invalid client configuration returns
  `{:error, %TypeSafe.Error{kind: :configuration}}` with a safe description.
  Process registration failures follow normal `GenServer.start_link/3` behavior.

  ## Examples

      iex> {:error, error} = TypeSafe.Client.start_link(api_key: "")
      iex> error.kind
      :configuration
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    with {:ok, config} <- Config.new(opts) do
      start_configured(config)
    end
  end

  defp start_configured(%{pool_size: 1} = config) do
    GenServer.start_link(__MODULE__, config, if(config.name, do: [name: config.name], else: []))
  end

  defp start_configured(config), do: Pool.start_link(config)

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    pooled = Keyword.get(opts, :pool_size, 1) != 1

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: if(pooled, do: :supervisor, else: :worker),
      shutdown: if(pooled, do: :infinity, else: 5_000)
    }
  end

  @doc false
  @spec evaluate(GenServer.server(), map()) :: {:ok, Response.t()} | {:error, Error.t()}
  def evaluate(client, request) do
    case Pool.evaluate(client, Map.delete(request, :schema)) do
      {:decode, body, deadline, id, attempts} ->
        result = decode(body, request.schema, deadline)
        emit_stop(request.started, attempts, id, result)
        result

      result ->
        result
    end
  catch
    :exit, _reason -> {:error, Error.new(:unavailable, "Client is unavailable")}
  end

  @impl true
  def init({config, pool, routing}) do
    {:ok, _owner} = Registry.register(TypeSafe.PoolRegistry, pool, routing)
    init(config)
  end

  def init(config) do
    {:ok, _owner} = Registry.register(TypeSafe.PoolRegistry, self(), {:connection, config.model})

    {:ok,
     %{
       config: config,
       conn: nil,
       connector: nil,
       requests: %{},
       refs: %{},
       uploads: MapSet.new(),
       queue: :queue.new()
     }}
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
    body = request.input.body
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
            uploads: MapSet.put(state.uploads, id),
            requests: Map.put(state.requests, id, request)
        }

        upload(state, id)

      {:error, conn, _reason} ->
        state |> Map.put(:conn, conn) |> transport_failure(id) |> disconnect()
    end
  end

  defp flush_uploads(state) do
    Enum.reduce(state.uploads, state, &upload(&2, &1))
  end

  defp upload(%{conn: nil} = state, _id), do: state

  defp upload(state, id) do
    current_time = now()

    case state.requests[id] do
      %{deadline: deadline} when deadline <= current_time ->
        abandon(state, id, {:error, Error.new(:timeout, "Request deadline exceeded")})

      %{upload: body, ref: ref, upload_scheduled: false, input: %{body: original}}
      when is_binary(body) ->
        window = Mint.HTTP.request_body_window(state.conn, ref)

        budget =
          if byte_size(original) <= @buffered_upload_bytes,
            do: @buffered_upload_chunk_bytes,
            else: @upload_chunk_bytes

        size = max(0, min(byte_size(body), min(window, budget)))
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

        cond do
          data == :eof ->
            %{state | uploads: MapSet.delete(state.uploads, id)}

          rest == "" ->
            # Mint HTTP/1 cannot parse the response until it receives :eof.
            # Finalize before yielding, since the server now has the full body.
            upload(state, id)

          true ->
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
        finish(state, id, {:decode, body})

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

      state = %{state | uploads: MapSet.delete(state.uploads, id)}

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
    cancel_timer(r.timer)
    cancel_timer(r.retry_timer)
    Process.demonitor(r.monitor, [:flush])
    deliver(r, id, result)

    %{
      state
      | requests: requests,
        refs: Map.delete(state.refs, r.ref),
        uploads: MapSet.delete(state.uploads, id),
        queue:
          if(r.phase == :queued, do: :queue.filter(&(&1 != id), state.queue), else: state.queue)
    }
  end

  defp deliver(request, id, {:decode, body}) do
    GenServer.reply(request.from, {:decode, body, request.deadline, id, request.attempt})
  end

  defp deliver(request, id, result) do
    if result != :caller_down, do: GenServer.reply(request.from, result)
    emit_stop(request.input.started, request.attempt, id, result)
  end

  defp decode(body, schema, deadline) do
    if now() >= deadline do
      {:error, Error.new(:timeout, "Request deadline exceeded")}
    else
      result = Response.decode(body, schema)

      if now() >= deadline,
        do: {:error, Error.new(:timeout, "Request deadline exceeded")},
        else: result
    end
  end

  defp emit_stop(started, attempts, id, result) do
    emit(
      :stop,
      Map.merge(%{duration: now() - started, attempts: attempts}, usage(result)),
      %{request_id: id, outcome: outcome(result)}
    )
  end

  defp disconnect(state) do
    close(state.conn)
    ids = Map.values(state.refs)
    state = %{state | conn: nil, refs: %{}, uploads: MapSet.new()}

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
  defp cancel_timer(timer), do: Process.cancel_timer(timer, async: true, info: false)
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
