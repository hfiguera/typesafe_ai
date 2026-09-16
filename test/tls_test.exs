defmodule TypeSafe.TLSTest do
  use ExUnit.Case, async: true

  alias TypeSafe.{Client, Error, H2Server, TestServer}

  defp certificate, do: Path.expand("fixtures/server-cert.pem", __DIR__)
  defp key, do: Path.expand("fixtures/server-key.pem", __DIR__)

  defp server(handler, options \\ []) do
    socket_options =
      [certfile: String.to_charlist(certificate()), keyfile: String.to_charlist(key())] ++ options

    start_supervised!(
      {TestServer, handler: handler, transport: :ssl, socket_options: socket_options}
    )
  end

  defp client(server, opts \\ []) do
    defaults = [
      api_key: "test-secret",
      base_url: TestServer.url(server),
      transport_opts: [cacertfile: String.to_charlist(Path.expand("fixtures/ca.pem", __DIR__))]
    ]

    start_supervised!({Client, Keyword.merge(defaults, opts)})
  end

  defp evaluate(client, opts \\ []) do
    TypeSafe.system_one(
      client,
      Keyword.merge([state: "hello", questions: %{"check" => TypeSafe.noul("True?")}], opts)
    )
  end

  test "verifies HTTPS using an explicit CA file" do
    server = server(fn _request -> {:reply, 200, TestServer.success(), []} end)
    assert {:ok, _} = server |> client() |> evaluate()
  end

  @tag capture_log: true
  test "rejects an untrusted certificate" do
    server = server(fn _request -> {:reply, 200, TestServer.success(), []} end)
    client = client(server, transport_opts: [cacerts: []])
    assert {:error, %Error{kind: :transport}} = evaluate(client)
  end

  @tag capture_log: true
  test "rejects a trusted certificate with the wrong hostname" do
    server = server(fn _request -> {:reply, 200, TestServer.success(), []} end)
    url = String.replace(TestServer.url(server), "localhost", "127.0.0.1")
    client = client(server, base_url: url)
    assert {:error, %Error{kind: :transport}} = evaluate(client)
  end

  test "HTTP/2 stream errors leave other streams usable" do
    owner = self()

    server =
      server({:raw, fn transport, socket -> H2Server.serve(transport, socket, owner) end},
        alpn_preferred_protocols: ["h2"]
      )

    client = client(server)
    failed = Task.async(fn -> evaluate(client) end)
    assert_receive {:h2_request, worker, stream1, _headers, _body}, 2_000
    healthy = Task.async(fn -> evaluate(client) end)
    assert_receive {:h2_request, ^worker, stream2, _headers, _body}
    send(worker, {:reset, stream1})
    assert {:error, %Error{kind: :transport}} = Task.await(failed)
    send(worker, {:respond, stream2, TestServer.success()})
    assert {:ok, _} = Task.await(healthy)
  end

  test "HTTP/2 drains accepted streams after GOAWAY and reconnects queued work" do
    owner = self()

    server =
      server({:raw, fn transport, socket -> H2Server.serve(transport, socket, owner) end},
        alpn_preferred_protocols: ["h2"]
      )

    client = client(server, max_concurrency: 1)
    first = Task.async(fn -> evaluate(client) end)
    assert_receive {:h2_request, worker, stream1, _headers, _body}, 2_000
    send(worker, {:goaway, stream1})
    second = Task.async(fn -> evaluate(client) end)
    refute_receive {:h2_request, _, _, _, _}, 50
    send(worker, {:respond, stream1, TestServer.success()})
    assert {:ok, _} = Task.await(first)
    assert_receive {:h2_request, worker2, stream2, _headers, _body}, 2_000
    assert worker2 != worker
    send(worker2, {:respond, stream2, TestServer.success()})
    assert {:ok, _} = Task.await(second)
  end

  test "HTTP/2 multiplexes, respects stream limits, and correlates reversed responses" do
    owner = self()

    server =
      server({:raw, fn transport, socket -> H2Server.serve(transport, socket, owner) end},
        alpn_preferred_protocols: ["h2"]
      )

    client = client(server, max_concurrency: 10)
    first = Task.async(fn -> evaluate(client) end)
    assert_receive {:h2_request, worker, stream1, headers, _body}, 2_000
    assert {":path", "/v1/systemone"} in headers
    second = Task.async(fn -> evaluate(client) end)
    assert_receive {:h2_request, ^worker, stream2, _headers, _body}
    third = Task.async(fn -> evaluate(client) end)
    refute_receive {:h2_request, _, _, _, _}, 50
    send(worker, {:respond, stream2, TestServer.success(0.2)})
    assert {:ok, response} = Task.await(second)
    assert response.answers["check"].noul == 0.2
    assert_receive {:h2_request, ^worker, stream3, _headers, _body}
    send(worker, {:respond, stream3, TestServer.success(0.3)})
    send(worker, {:respond, stream1, TestServer.success(0.1)})
    assert {:ok, response} = Task.await(first)
    assert response.answers["check"].noul == 0.1
    assert {:ok, response} = Task.await(third)
    assert response.answers["check"].noul == 0.3
  end

  test "HTTP/2 uploads beyond flow-control windows and cancels only the expired stream" do
    owner = self()

    server =
      server({:raw, fn transport, socket -> H2Server.serve(transport, socket, owner) end},
        alpn_preferred_protocols: ["h2"]
      )

    client = client(server)
    large = String.duplicate("a", 90_000)
    upload = Task.async(fn -> evaluate(client, state: large) end)
    assert_receive {:h2_request, worker, stream1, _headers, body}, 2_000
    assert JSON.decode!(body)["state"] == large
    expiring = Task.async(fn -> evaluate(client, timeout: 100) end)
    assert_receive {:h2_request, ^worker, stream2, _headers, _body}
    assert {:error, %Error{kind: :timeout}} = Task.await(expiring)
    assert_receive {:h2_cancel, ^stream2}
    send(worker, {:respond, stream1, TestServer.success()})
    assert {:ok, _} = Task.await(upload)
  end
end
