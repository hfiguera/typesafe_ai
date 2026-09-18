defmodule TypeSafe.Bench.LoadTest do
  use ExUnit.Case, async: false
  alias TypeSafe.Bench.{Curves, Load, Server}

  for storage <- ["ets", "list"] do
    @storage storage
    test "#{@storage} driver accounts for capacity drops" do
      count = :atomics.new(1, [])

      call = fn _ ->
        case :atomics.add_get(count, 1, 1) do
          1 ->
            Process.sleep(40)
            {:ok, nil}

          2 ->
            {:error, %{kind: :deadline}}

          _ ->
            exit(:test_crash)
        end
      end

      result =
        Load.drive(call, %{small: [], regular: [], large_every: 2},
          rate: 1000,
          requests: 80,
          max_in_flight: 1,
          sample_storage: @storage
        )

      assert result.dropped > 0
      assert length(result.samples) + result.dropped == 80
      assert Enum.any?(result.samples, &(elem(&1, 1) == :ok))
      assert result.pending == %{}
      assert Enum.sum(Enum.map(result.timeline, & &1.offered_requests)) == 80
      assert Enum.sum(Enum.map(result.timeline, & &1.driver_dropped)) == result.dropped

      assert Enum.sum(
               for bucket <- result.timeline, count <- Map.values(bucket.outcomes), do: count
             ) == length(result.samples)

      refute_receive {:DOWN, _, _, _, _}
    end
  end

  for storage <- ["ets", "list"] do
    @storage storage
    test "#{@storage} driver preserves failures and crashes without losing samples" do
      count = :atomics.new(1, [])

      call = fn _ ->
        case :atomics.add_get(count, 1, 1) do
          1 -> {:ok, nil}
          2 -> {:error, %{kind: :deadline}}
          3 -> exit(:test_crash)
        end
      end

      result =
        Load.drive(call, %{small: [], regular: [], large_every: 0},
          rate: 1000,
          requests: 3,
          max_in_flight: 3,
          sample_storage: @storage
        )

      assert Enum.frequencies_by(result.samples, &elem(&1, 1)) == %{
               ok: 1,
               deadline: 1,
               driver_crash: 1
             }

      assert result.dropped == 0
      assert result.pending == %{}
    end
  end

  test "scheduled arrivals continue while earlier calls are pending" do
    parent = self()

    call = fn _ ->
      send(parent, {:started, self()})

      receive do
        :release -> {:ok, nil}
      after
        2000 -> {:error, :test_timeout}
      end
    end

    driver =
      Task.async(fn ->
        Load.drive(call, %{small: [], regular: [], large_every: 0},
          rate: 100,
          requests: 4,
          max_in_flight: 4
        )
      end)

    # All four must start before any finishes. A closed-loop driver cannot do so.
    workers =
      for _ <- 1..4 do
        assert_receive {:started, pid}, 1000
        pid
      end

    Enum.each(workers, &send(&1, :release))
    result = Task.await(driver)
    assert result.dropped == 0
    assert length(result.samples) == 4
    assert Enum.all?(result.samples, &(elem(&1, 1) == :ok))
  end

  test "good success percentiles cannot conceal errors, drops, lag, or small samples" do
    config = %{budget_ms: 20, lag_budget_ms: 5, min_samples: 1000}

    row = %{
      outcomes: %{ok: 1000},
      offered_requests: 1000,
      driver_dropped: 0,
      driver_launch_lag_ms: %{p99: 1},
      success_latency_from_scheduled_arrival_ms: %{p99: 10},
      within_budget_fraction_of_offered: 1.0
    }

    assert Curves.qualify(row, config).passes

    for altered <- [
          %{row | outcomes: %{ok: 999, deadline: 1}},
          %{row | driver_dropped: 1},
          %{row | driver_launch_lag_ms: %{p99: 6}},
          %{row | success_latency_from_scheduled_arrival_ms: %{p99: 21}},
          %{row | within_budget_fraction_of_offered: 0.98}
        ] do
      refute Curves.qualify(altered, config).passes
    end
  end

  test "a higher isolated passing rate does not erase lower-rate failures" do
    rows =
      for {rate, repetition, pass} <- [
            {100, 1, true},
            {100, 2, true},
            {200, 1, true},
            {200, 2, false},
            {300, 1, true},
            {300, 2, true}
          ] do
        %{
          client: "typesafe",
          connections: 1,
          workload: "small",
          offered_rps: rate,
          repetition: repetition,
          budget_check: %{passes: pass, reasons: if(pass, do: [], else: ["p99_budget"])}
        }
      end

    assert [%{highest_tested_passing_offered_rps: 100, all_tested_rates_pass: false}] =
             Curves.capacities(rows)
  end

  test "live mode refuses load overrides before making requests" do
    previous = System.get_env("TYPESAFE_API_KEY")
    System.put_env("TYPESAFE_API_KEY", "not-a-real-key")

    try do
      assert_raise ArgumentError, ~r/request budget is fixed/, fn ->
        Curves.run(["--live", "--rates", "1000"])
      end
    after
      if previous,
        do: System.put_env("TYPESAFE_API_KEY", previous),
        else: System.delete_env("TYPESAFE_API_KEY")
    end
  end

  test "each adapter's load report accounts for warmup, models, usage and mixed traffic" do
    {:ok, server} = Server.start_link(0)
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    old = System.get_env("BENCH_PORT")
    System.put_env("BENCH_PORT", to_string(port))

    try do
      for client <- ~w(typesafe finch req req_llm) do
        report =
          Load.measure(
            client: client,
            rate: 100,
            requests: 20,
            warmup: 2,
            large_every: 4,
            bytes: 2048,
            delay: 0
          )

        assert report.outcomes == %{ok: 20}
        assert report.driver_dropped == 0
        assert report.models == ["jev-benchmark"]
        assert report.observed_usage_including_warmup == %{input_tokens: 264, output_tokens: 44}
        assert report.workloads.small.outcomes == %{ok: 15}
        assert report.workloads.large.outcomes == %{ok: 5}

        assert report.success_latency_from_scheduled_arrival_ms.p99 >=
                 report.success_latency_ms.p99

        assert report.vm_cpu_ms >= 0
      end
    after
      if old, do: System.put_env("BENCH_PORT", old), else: System.delete_env("BENCH_PORT")
      Supervisor.stop(server)
    end
  end
end
