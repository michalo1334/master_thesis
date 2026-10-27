defmodule NetworkDefense.Evaluation.Study.FinalTimingTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Evaluation.Study.Timing.{Interval, Recorder, ReplicaTiming}

  @events [:plan_dispatch, :plan_completion, :simulation_dispatch, :simulation_completion]

  test "FINAL-TIMING-01: WHEN ordered boundaries overlap, THE recorder SHALL build direct intervals" do
    recorder = record_position(Recorder.new("core"), 0, [100, 160, 150, 250])
    recorder = Enum.reduce(1..4, recorder, &record_position(&2, &1, [100, 120, 130, 180]))

    assert {:ok, timings} = Recorder.complete(recorder)
    assert Enum.map(timings, & &1.position) == Enum.to_list(0..4)
    assert [%ReplicaTiming{} = timing | _rest] = timings
    assert timing.tier == "core"
    assert timing.plan_selection.elapsed_us == 60
    assert timing.simulation.elapsed_us == 100
    assert timing.total.elapsed_us == 150
  end

  test "FINAL-TIMING-02: WHEN a boundary repeats, THE recorder SHALL keep the first reading without calling the clock" do
    clock = fn ->
      send(self(), :clock_read)
      100
    end

    assert {:ok, recorder} =
             Recorder.record(Recorder.new("core"), "core", 0, :plan_dispatch, clock)

    assert_received :clock_read
    assert {:ok, ^recorder} = Recorder.record(recorder, "core", 0, :plan_dispatch, clock)
    refute_received :clock_read
  end

  test "FINAL-TIMING-03: WHEN a boundary is invalid, THE recorder SHALL reject it and all later boundaries" do
    for {tier, position, event, reason} <- [
          {"core", 0, :unknown, :invalid_event},
          {"core", 5, :plan_dispatch, :invalid_position},
          {"core", -1, :plan_dispatch, :invalid_position},
          {"core", 0.0, :plan_dispatch, :invalid_position},
          {"edge", 0, :plan_dispatch, :unexpected_tier},
          {"core", 0, :plan_completion, :out_of_order}
        ] do
      clock = fn -> flunk("invalid events must not read the clock") end

      assert {:error, ^reason, failed} =
               Recorder.record(Recorder.new("core"), tier, position, event, clock)

      assert {:error, :terminal_failure, ^failed} =
               Recorder.record(failed, "core", 0, :plan_dispatch, clock)

      assert {:error, :terminal_failure} = Recorder.complete(failed)
    end
  end

  test "FINAL-TIMING-04: WHEN boundaries are missing or reversed, THE recorder SHALL reject completion" do
    assert {:error, :incomplete} = Recorder.complete(Recorder.new("core"))

    recorder =
      Enum.reduce(0..4, Recorder.new("core"), &record_position(&2, &1, [100, 90, 130, 180]))

    assert {:error, :invalid_interval} = Recorder.complete(recorder)
  end

  test "FINAL-TIMING-05: WHEN timing attributes are invalid, THE contract SHALL reject them" do
    attrs = %{
      tier: "core",
      position: 0,
      plan_selection: %Interval{elapsed_us: 1},
      simulation: %Interval{elapsed_us: 2},
      total: %Interval{elapsed_us: 3}
    }

    assert {:ok, %ReplicaTiming{}} = ReplicaTiming.new(attrs)

    for patch <- [
          %{tier: " "},
          %{position: -1},
          %{position: 5},
          %{plan_selection: %{elapsed_us: 1}},
          %{total: %Interval{elapsed_us: -1}}
        ] do
      assert :error = ReplicaTiming.new(Map.merge(attrs, patch))
    end
  end

  defp record_position(recorder, position, readings) do
    Enum.zip(@events, readings)
    |> Enum.reduce(recorder, fn {event, reading}, recorder ->
      {:ok, recorder} = Recorder.record(recorder, "core", position, event, fn -> reading end)
      recorder
    end)
  end
end
