defmodule TypeSafe.Bench.TransportTest do
  use ExUnit.Case, async: false
  alias TypeSafe.Bench.{Server, Transport}

  setup do
    previous_key = System.get_env("TYPESAFE_API_KEY")
    System.put_env("TYPESAFE_API_KEY", "must-not-reach-offline-fixture")

    on_exit(fn ->
      if previous_key,
        do: System.put_env("TYPESAFE_API_KEY", previous_key),
        else: System.delete_env("TYPESAFE_API_KEY")
    end)

    :ok
  end

  for client <- ["typesafe", "finch", "req", "req_llm"],
      protocol <- [:http1, :http2],
      status <- [200, 503] do
    @client client
    @protocol protocol
    @status status

    test "#{client} #{protocol} sends matching wire input and handles HTTP #{status}" do
      previous_port = System.get_env("BENCH_PORT")
      {:ok, server} = Server.start_link(0, observer: self(), status: @status)
      {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
      System.put_env("BENCH_PORT", to_string(port))

      on_exit(fn ->
        if previous_port,
          do: System.put_env("BENCH_PORT", previous_port),
          else: System.delete_env("BENCH_PORT")
      end)

      scenario = %{
        client: @client,
        protocol: @protocol,
        connections: 2,
        delay: 0,
        max_concurrency: 10,
        max_queue: 100
      }

      {call, stop} = Transport.start(scenario)
      state = %{"text" => "café ☕", "items" => [1, true, nil]}
      questions = Map.new(1..32, &{"q#{&1}", TypeSafe.noul("Is this true?")})
      {:ok, wire} = TypeSafe.Question.to_wire(questions)

      input =
        Transport.input(@client,
          state: state,
          questions: questions,
          timeout: 5000,
          retry: [max_attempts: 1]
        )

      try do
        result = Transport.ready(call, input)
        assert_receive {:fixture_request, observed}, 1000
        assert observed.method == "POST"
        assert observed.path == "/0/v1/systemone"
        assert observed.authorization == ["Bearer benchmark-only"]
        assert observed.protocol == if(@protocol == :http2, do: :"HTTP/2", else: :"HTTP/1.1")

        assert observed.body ==
                 JSON.decode!(
                   JSON.encode!(%{
                     model: "jev-benchmark",
                     state: state,
                     questions: wire
                   })
                 )

        if @status == 200 do
          assert {:ok, response} = result
          assert response.model == "jev-benchmark"

          if @client == "req_llm" do
            assert map_size(response.object) == 32

            assert Enum.all?(response.object, fn {_id, answer} ->
                     answer == %{"type" => "boolean", "probability" => 0.9}
                   end)

            assert response.provider_meta.raw_response["usage"] == %{
                     "input_tokens" => 12,
                     "output_tokens" => 2
                   }
          else
            assert map_size(response.answers) == 32
            assert Enum.all?(response.answers, fn {_id, answer} -> answer.noul == 0.9 end)
            assert response.usage == %{input_tokens: 12, output_tokens: 2}
          end
        else
          assert {:error, _} = result
          # Disabled retries must not turn HTTP failures into repeated evaluations.
          refute_receive {:fixture_request, _}, 50
        end
      after
        stop.()
        Supervisor.stop(server)
      end
    end
  end
end
