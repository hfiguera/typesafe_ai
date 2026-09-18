defmodule TypeSafe.Bench.CommunityTest do
  use ExUnit.Case, async: false
  alias TypeSafe.Bench.{Recordings, Server, Transport}

  setup do
    old = System.get_env("BENCH_PORT")

    on_exit(fn ->
      if old, do: System.put_env("BENCH_PORT", old), else: System.delete_env("BENCH_PORT")
    end)

    :ok
  end

  defp scenario(client, extra \\ %{}) do
    Map.merge(
      %{
        client: client,
        protocol: :http2,
        connections: 1,
        delay: 0,
        max_concurrency: 10,
        max_queue: 100
      },
      extra
    )
  end

  defp fixture(opts) do
    {:ok, server} = Server.start_link(0, [observer: self()] ++ opts)
    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    System.put_env("BENCH_PORT", to_string(port))
    {server, port}
  end

  for client <- ~w(jev typesafe_api) do
    @client client
    test "#{client} matches all eight recorded requests and answers over verified HTTP/2" do
      recordings = Recordings.load()
      {server, _} = fixture(recordings: recordings)

      try do
        for {id, r} <- Enum.sort(recordings) do
          {call, stop} = Transport.start(scenario(@client, %{recording: r}))

          try do
            input = Transport.input(@client, r.input ++ [timeout: 5000])
            assert {:ok, result} = Transport.ready(call, input)
            assert_receive {:fixture_request, observed}
            assert observed.protocol == :"HTTP/2"
            assert observed.authorization == ["Bearer benchmark-only"]
            assert observed.path == "/0/recorded/#{id}/v1/systemone"
            assert Server.canonical_request(observed.body) == r.request
            assert result.model == r.response.model
            assert result.usage.input_tokens == r.response.usage.input_tokens
            assert result.usage.output_tokens == r.response.usage.output_tokens

            for {key, expected} <- r.response.answers do
              if @client == "jev" do
                key = String.to_existing_atom(key)

                case expected do
                  %TypeSafe.Answer.Noul{noul: p} ->
                    assert result[key] == p

                  %TypeSafe.Answer.Choice{choice: choice, confidence: c, probabilities: ps} ->
                    assert Atom.to_string(result[key]) == choice
                    assert result.confidence[key] == c

                    assert Map.new(result.probabilities[key], fn {k, v} -> {to_string(k), v} end) ==
                             ps

                  %TypeSafe.Answer.Score{score: score, confidence: c, probabilities: ps} ->
                    assert result[key] == score
                    assert result.confidence[key] == c

                    assert Map.new(result.probabilities[key], fn {k, v} -> {to_string(k), v} end) ==
                             ps
                end
              else
                actual = result.answers[key]

                for field <- [:noul, :choice, :score, :confidence, :probabilities] do
                  if Map.has_key?(expected, field) do
                    value = Map.fetch!(actual, field)

                    value =
                      if is_map(value),
                        do: Map.new(value, fn {k, v} -> {to_string(k), v} end),
                        else: value

                    assert value == Map.fetch!(expected, field)
                  end
                end
              end
            end
          after
            stop.()
          end
        end
      after
        Supervisor.stop(server)
      end
    end

    for status <- [429, 529, 503] do
      @status status
      test "#{client} disables retries for HTTP #{status}" do
        {server, _} = fixture(status: @status)
        {call, stop} = Transport.start(scenario(@client))

        try do
          input =
            Transport.input(@client,
              state: "test",
              questions: %{"q1" => TypeSafe.noul("True?")},
              timeout: 1000
            )

          assert {:error, %{status: @status}} = Transport.ready(call, input)
          assert_receive {:fixture_request, _}
          refute_receive {:fixture_request, _}, 100
        after
          stop.()
          Supervisor.stop(server)
        end
      end
    end
  end

  for {client, protocol} <- [
        {"typesafe", :"HTTP/2"},
        {"jev", :"HTTP/1.1"},
        {"typesafe_api", :"HTTP/1.1"}
      ] do
    @client client
    @protocol protocol
    test "#{client} default connection profile uses #{protocol}" do
      {server, _} = fixture([])
      {call, stop} = Transport.start(scenario(@client, %{profile: "defaults"}))

      try do
        input =
          Transport.input(@client,
            state: "test",
            questions: %{"q1" => TypeSafe.noul("True?")},
            timeout: 1000
          )

        assert {:ok, _} = Transport.ready(call, input)
        assert_receive {:fixture_request, %{protocol: @protocol}}
      after
        stop.()
        Supervisor.stop(server)
      end
    end
  end

  test "Jev's optional null criteria is the only replay normalization" do
    r = Recordings.load()["noul_small"].request
    assert Server.canonical_request(put_in(r, ["questions", "refund", "criteria"], nil)) == r

    refute Server.canonical_request(put_in(r, ["questions", "refund", "instructions"], "changed")) ==
             r
  end

  test "typesafe_sdk native HTTP/1 transport evaluates a local fixture" do
    {server, port} = fixture(scheme: :http)

    try do
      client =
        TypeSafeSDK.new_client(
          api_key: "benchmark-only",
          base_url: "http://localhost:#{port}/0",
          model: "jev-benchmark",
          retry: false,
          timeout_ms: 1000
        )

      assert {:ok, response} =
               TypeSafeSDK.evaluate(client, "test", %{"q1" => TypeSafeSDK.noul("True?")})

      assert response.answers["q1"].noul == 0.9
      assert_receive {:fixture_request, observed}
      assert observed.protocol == :"HTTP/1.1"
      assert observed.authorization == ["Bearer benchmark-only"]
    after
      Supervisor.stop(server)
    end
  end

  test "typesafe_sdk default adapter verifies HTTPS with a VM-local fixture CA" do
    {server, _} = fixture([])

    {call, stop} =
      Transport.start(scenario("typesafe_sdk", %{profile: "defaults", target: :offline}))

    try do
      input =
        Transport.input("typesafe_sdk",
          state: "test",
          questions: %{"q1" => TypeSafe.noul("True?")},
          timeout: 1000
        )

      assert {:ok, response} = call.(input)
      assert response.answers["q1"].noul == 0.9

      assert_receive {:fixture_request,
                      %{protocol: :"HTTP/1.1", authorization: ["Bearer benchmark-only"]}}
    after
      stop.()
      Supervisor.stop(server)
    end
  end

  test "typesafe_sdk 0.3.0 does not forward custom CA through its native transport" do
    {server, port} = fixture([])

    try do
      ca = Path.expand("../../test/fixtures/ca.pem", __DIR__) |> String.to_charlist()

      client =
        TypeSafeSDK.new_client(
          api_key: "benchmark-only",
          base_url: "https://localhost:#{port}/0",
          retry: false,
          timeout_ms: 1000,
          transport_opts: [cacertfile: ca, transport_opts: [cacertfile: ca]]
        )

      assert {:error, %{type: :connection, message: message}} =
               TypeSafeSDK.evaluate(client, "test", %{"q1" => TypeSafeSDK.noul("True?")})

      assert message =~ "unknown_ca"
      refute_receive {:fixture_request, _}, 100
    after
      Supervisor.stop(server)
    end
  end
end
