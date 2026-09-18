defmodule TypeSafe.Bench.Server do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def start_link(port, opts \\ []) do
    fixtures = Path.expand("../../test/fixtures", __DIR__)

    Bandit.start_link(
      plug: {__MODULE__, opts},
      scheme: :https,
      ip: Keyword.get(opts, :ip, {127, 0, 0, 1}),
      port: port,
      certfile: Path.join(fixtures, "server-cert.pem"),
      keyfile: Path.join(fixtures, "server-key.pem"),
      http_2_options: [default_local_settings: [max_concurrent_streams: 1024]],
      http_options: [compress: false],
      startup_log: false
    )
  end

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    {body, conn} = read_all(conn, [])
    request = JSON.decode!(body)

    if observer = opts[:observer] do
      send(
        observer,
        {:fixture_request,
         %{
           method: conn.method,
           path: conn.request_path,
           protocol: get_http_protocol(conn),
           authorization: get_req_header(conn, "authorization"),
           body: request
         }}
      )
    end

    {status, response} = response(conn.path_info, request, opts)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(Keyword.get(opts, :status, status), response)
  end

  # Recorded replies preserve the exact captured bytes. Semantic request matching
  # accepts different JSON key order while rejecting a different workload.
  defp response([delay, "recorded", id, "v1", "systemone"], request, opts) do
    case Map.get(Keyword.get(opts, :recordings, %{}), id) do
      %{request: ^request, response_body: body} ->
        Process.sleep(String.to_integer(delay))
        {200, body}

      nil ->
        {404, ~s({"error":"unknown_recording"})}

      _ ->
        {409, ~s({"error":"recording_request_mismatch"})}
    end
  end

  defp response([delay, "v1", "systemone"], request, _opts) do
    Process.sleep(String.to_integer(delay))

    answers =
      Map.new(request["questions"], fn {id, _question} ->
        {id, %{type: "noul", noul: 0.9}}
      end)

    response =
      JSON.encode!(%{
        model: request["model"],
        answers: answers,
        usage: %{input_tokens: 12, output_tokens: 2}
      })

    {200, response}
  end

  defp response(_path, _request, _opts), do: {404, ~s({"error":"unknown_fixture"})}

  defp read_all(conn, chunks) do
    case read_body(conn) do
      {:more, body, conn} -> read_all(conn, [body | chunks])
      {:ok, body, conn} -> {IO.iodata_to_binary(Enum.reverse([body | chunks])), conn}
    end
  end
end
