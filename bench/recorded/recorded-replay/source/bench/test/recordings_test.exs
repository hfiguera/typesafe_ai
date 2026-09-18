defmodule TypeSafe.Bench.RecordingsTest do
  use ExUnit.Case, async: false
  alias TypeSafe.Bench.{Capture, Load, Recordings, Server, Transport}

  setup do
    old_port = System.get_env("BENCH_PORT")
    old_key = System.get_env("TYPESAFE_API_KEY")
    System.put_env("TYPESAFE_API_KEY", "must-not-reach-replay-fixture")
    recordings = Recordings.load()
    {:ok, server} = Server.start_link(0, recordings: recordings, observer: self())
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    System.put_env("BENCH_PORT", to_string(port))

    on_exit(fn ->
      for {key, value} <- [{"BENCH_PORT", old_port}, {"TYPESAFE_API_KEY", old_key}] do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    %{recordings: recordings, server: server, port: port}
  end

  for client <- ~w(typesafe finch req req_llm), protocol <- [:http1, :http2] do
    @client client
    @protocol protocol
    test "#{client} #{protocol} replays all captured shapes and sends the same service input", %{
      recordings: recordings
    } do
      for {id, recording} <- Enum.sort(recordings) do
        s = %{
          client: @client,
          protocol: @protocol,
          recording: recording,
          connections: 2,
          delay: 0,
          max_concurrency: 10,
          max_queue: 100
        }

        {call, stop} = Transport.start(s)

        input =
          Transport.input(@client, recording.input ++ [timeout: 5000, retry: [max_attempts: 1]])

        try do
          assert {:ok, response} = Transport.ready(call, input)
          assert_receive {:fixture_request, observed}, 1000
          assert observed.body == recording.request
          assert observed.path == "/0/recorded/#{id}/v1/systemone"
          assert observed.authorization == ["Bearer benchmark-only"]
          assert observed.protocol == if(@protocol == :http2, do: :"HTTP/2", else: :"HTTP/1.1")

          if @client == "req_llm" do
            assert response.provider_meta.raw_response == JSON.decode!(recording.response_body)
            assert map_size(response.object) == map_size(recording.request["questions"])
          else
            assert response == recording.response
          end
        after
          stop.()
        end
      end
    end
  end

  test "replay preserves exact response bytes and rejects changed or unknown requests", %{
    recordings: recordings,
    port: port
  } do
    recording = recordings["mixed_batch"]

    {:ok, pool} =
      Finch.start_link(
        name: RawReplayTest,
        pools: %{
          :default => [
            protocols: [:http2],
            conn_opts: [
              transport_opts: [
                cacertfile:
                  Path.expand("../../test/fixtures/ca.pem", __DIR__) |> String.to_charlist()
              ]
            ]
          ]
        }
      )

    call = fn {id, request} ->
      Finch.build(
        :post,
        "https://localhost:#{port}/0/recorded/#{id}/v1/systemone",
        [{"content-type", "application/json"}],
        JSON.encode!(request)
      )
      |> Finch.request(RawReplayTest)
    end

    try do
      assert {:ok, %{status: 200, body: body}} =
               Transport.ready(call, {recording.id, recording.request})

      assert body == recording.response_body

      assert {:ok, %{status: 409}} =
               call.({recording.id, Map.put(recording.request, "state", "different workload")})

      assert {:ok, %{status: 404}} = call.({"missing", recording.request})
    after
      Supervisor.stop(pool)
    end
  end

  test "loader rejects modified capture bodies", %{recordings: recordings} do
    dir =
      Path.join(System.tmp_dir!(), "typesafe-recordings-#{System.unique_integer([:positive])}")

    File.cp_r!(Recordings.default_path(), dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    assert map_size(recordings) == 8
    File.write!(Path.join(dir, "noul_small.response.json"), "{}")
    assert_raise MatchError, fn -> Recordings.load(dir) end
  end

  for client <- ~w(typesafe req_llm) do
    @client client
    test "load driver measures #{@client} recorded batch and labels replayed usage", %{
      recordings: recordings
    } do
      report =
        Load.measure(
          client: @client,
          recording: "batch_32",
          rate: 100,
          requests: 20,
          connections: 2,
          delay: 0
        )

      assert report.recording_id == "batch_32"
      assert report.outcomes == %{ok: 20}
      assert report.driver_dropped == 0
      assert report.questions == 32
      assert report.response_body_bytes == recordings["batch_32"].response_bytes
      assert report.usage_source == "recorded_response_replayed_not_live_usage"
      refute Map.has_key?(report, :recording)
    end
  end

  test "live capture requires explicit opt in" do
    assert_raise RuntimeError, fn -> Capture.run([]) end
  end
end
