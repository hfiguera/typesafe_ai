defmodule TypeSafe.TelemetryTest do
  use ExUnit.Case, async: false
  alias TypeSafe.{Client, TestServer}

  def record(event, measurements, metadata, owner),
    do: send(owner, {event, measurements, metadata})

  test "telemetry correlates attempts and exposes only counts and safe metadata" do
    handler = make_ref()
    events = Enum.map([:start, :retry, :stop], &[:typesafe, :request, &1])
    :ok = :telemetry.attach_many(handler, events, &__MODULE__.record/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)

    server =
      start_supervised!(
        {TestServer,
         handler: fn request ->
           if request.index == 1,
             do: {:reply, 429, "secret", [{"retry-after", "0"}]},
             else: {:reply, 200, TestServer.success(), []}
         end}
      )

    client = start_supervised!({Client, api_key: "secret", base_url: TestServer.url(server)})

    assert {:ok, _} =
             TypeSafe.system_one(client,
               state: "private-state",
               questions: %{"check" => TypeSafe.noul("private-question")}
             )

    assert_receive {[:typesafe, :request, :start], %{system_time: time}, %{request_id: id}}
    assert is_integer(time)

    assert_receive {[:typesafe, :request, :retry], %{delay: 0, attempt: 1},
                    %{request_id: ^id, status: 429}}

    assert_receive {[:typesafe, :request, :stop], measurements, metadata}
    assert measurements.attempts == 2
    assert measurements.duration >= 0
    assert measurements.input_tokens == 12
    assert metadata == %{request_id: id, outcome: :ok}
    refute inspect({measurements, metadata}) =~ "secret"
    refute inspect(:sys.get_status(client)) =~ "private"
  end
end
