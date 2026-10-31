defmodule NetworkDefense.Evaluation2.FinalTimingTest do
  @moduledoc """
  Clock ownership of Final collection timing.

  Cases: TIME-01 (ordered boundary readings summarized into five measured
  replicas, invalid boundary sequences rejected) and TIME-03 (a tier that lost
  its clock session fails instead of manufacturing a measurement).

  Every case injects its own reading sequence, so durations come from
  controlled monotonic microseconds. No case sleeps or depends on machine
  speed. Each case starts its own named service, so cases stay independent.
  """

  use ExUnit.Case, async: true
  @moduletag :unit
  @moduletag case_id: "TIME-01/TIME-03"

  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Final.{TierRun, Timing}
  alias NetworkDefense.Evaluation2.Study.Result.Timing, as: ResultTiming
  alias NetworkDefense.Evaluation2.Study.Result.Timing.{Replica, Tier}

  @phase_run_id "5f0d1f7a-3b8f-4c62-9a41-1f2c9b4d7e10"
  @other_phase_run_id "a1b2c3d4-5e6f-4a7b-8c9d-0e1f2a3b4c5d"

  # Plan-selection and simulation duration of replica positions zero to four.
  @durations for position <- 0..4, do: {120 + 10 * position, 480 + 20 * position}

  describe "boundary readings" do
    test "three ordered readings of each replica yield the measured durations" do
      name = start_service(readings(@durations))

      assert {:ok, session} = Timing.begin_tier(@phase_run_id, name)
      assert is_binary(session)
      assert byte_size(session) > 0

      for {{plan, simulation}, position} <- Enum.with_index(@durations) do
        assert {:ok, nil} = Timing.mark(session, position, :plan_start, name)
        assert {:ok, nil} = Timing.mark(session, position, :simulation_start, name)

        assert {:ok, %Replica{} = replica} =
                 Timing.mark(session, position, :replica_end, name)

        assert replica == %Replica{
                 plan_selection_us: plan,
                 simulation_us: simulation,
                 total_us: plan + simulation
               }
      end
    end

    test "a retried marker keeps its reading and the measured replica" do
      name = start_service(readings(@durations))
      {:ok, session} = Timing.begin_tier(@phase_run_id, name)

      {plan, simulation} = hd(@durations)

      assert {:ok, nil} = Timing.mark(session, 0, :plan_start, name)
      assert {:ok, nil} = Timing.mark(session, 0, :plan_start, name)
      assert {:ok, nil} = Timing.mark(session, 0, :simulation_start, name)
      assert {:ok, nil} = Timing.mark(session, 0, :simulation_start, name)

      assert {:ok, %Replica{} = first} = Timing.mark(session, 0, :replica_end, name)
      assert {:ok, ^first} = Timing.mark(session, 0, :replica_end, name)

      assert first == %Replica{
               plan_selection_us: plan,
               simulation_us: simulation,
               total_us: plan + simulation
             }
    end

    test "an invalid boundary sequence fails without disturbing later readings" do
      name = start_service(readings(@durations))
      {:ok, session} = Timing.begin_tier(@phase_run_id, name)

      assert {:error, %Error{}} = Timing.mark(session, 0, :simulation_start, name)
      assert {:error, %Error{}} = Timing.mark(session, 0, :replica_end, name)

      assert {:ok, nil} = Timing.mark(session, 0, :plan_start, name)
      assert {:error, %Error{}} = Timing.mark(session, 0, :replica_end, name)
      assert {:ok, nil} = Timing.mark(session, 0, :simulation_start, name)

      {plan, simulation} = hd(@durations)

      assert {:ok, %Replica{plan_selection_us: ^plan, simulation_us: ^simulation}} =
               Timing.mark(session, 0, :replica_end, name)

      # A rejected marker takes no reading, so the next replica keeps its own values.
      assert {:error, %Error{}} = Timing.mark(session, 2, :plan_start, name)
      assert {:ok, nil} = Timing.mark(session, 1, :plan_start, name)
      assert {:ok, nil} = Timing.mark(session, 1, :simulation_start, name)

      {next_plan, next_simulation} = Enum.at(@durations, 1)

      assert {:ok, %Replica{plan_selection_us: ^next_plan, simulation_us: ^next_simulation}} =
               Timing.mark(session, 1, :replica_end, name)
    end

    test "a position outside the measured range fails" do
      name = start_service(readings(@durations))
      {:ok, session} = Timing.begin_tier(@phase_run_id, name)

      assert {:error, %Error{}} = Timing.mark(session, 5, :plan_start, name)
      assert {:error, %Error{}} = Timing.mark(session, :first, :plan_start, name)
    end
  end

  describe "sessions" do
    test "a session of a replaced clock service is rejected" do
      name = unique_name()
      started = start_service(name, readings(@durations))

      {:ok, session} = Timing.begin_tier(@phase_run_id, name)
      assert {:ok, nil} = Timing.mark(session, 0, :plan_start, name)

      stop_supervised!(started)
      start_service(name, readings(@durations))

      assert {:error, %Error{}} = Timing.mark(session, 0, :simulation_start, name)
      assert {:error, %Error{}} = Timing.mark(session, 0, :replica_end, name)

      # The replacement service measures a tier under its own session.
      assert {:ok, replacement} = Timing.begin_tier(@phase_run_id, name)
      refute replacement == session
      assert {:ok, nil} = Timing.mark(replacement, 0, :plan_start, name)
    end

    test "a released session accepts no further marker" do
      name = start_service(readings(@durations))
      {:ok, session} = Timing.begin_tier(@phase_run_id, name)

      assert {:ok, nil} = Timing.mark(session, 0, :plan_start, name)
      assert {:ok, nil} = Timing.mark(session, 0, :simulation_start, name)
      assert {:ok, %Replica{}} = Timing.mark(session, 0, :replica_end, name)

      assert :ok = Timing.release(session, name)

      assert {:error, %Error{}} = Timing.mark(session, 1, :plan_start, name)

      # A released tier takes no new marker; the next tier opens its own session.
      assert {:ok, next_session} = Timing.begin_tier(@other_phase_run_id, name)
      refute next_session == session
      assert {:ok, nil} = Timing.mark(next_session, 0, :plan_start, name)
    end
  end

  describe "summaries" do
    test "three measured tiers keep their own raw replicas" do
      tier_runs = [tier_run(:small, 0), tier_run(:medium, 1_000), tier_run(:large, 2_000)]

      summary = Timing.summarize(tier_runs)

      assert %ResultTiming{by_tier: by_tier} = summary
      assert Enum.sort(Map.keys(by_tier)) == Enum.sort([:small, :medium, :large])

      assert ResultTiming.measurements(summary, :medium, :plan_selection) ==
               shifted(:plan_selection, 1_000)

      assert ResultTiming.measurements(summary, :large, :total) == shifted(:total, 2_000)
      assert ResultTiming.median(summary, :large, :plan_selection) == 2_140
      assert ResultTiming.range(summary, :small, :simulation) == {480, 560}
    end
  end

  # --- helpers -----------------------------------------------------------

  defp tier_run(tier, shift) do
    replicas =
      @durations
      |> Enum.with_index()
      |> Map.new(fn {{plan, simulation}, position} ->
        {position,
         %Replica{
           plan_selection_us: plan + shift,
           simulation_us: simulation + shift,
           total_us: plan + simulation + shift
         }}
      end)

    %TierRun{
      tier: tier,
      gust_run_id: shift + 1,
      phase_run_id: @phase_run_id,
      clock_session: "session-#{tier}",
      timing: %Tier{replicas: replicas}
    }
  end

  defp shifted(boundary, shift) do
    @durations
    |> Enum.with_index()
    |> Map.new(fn {{plan, simulation}, position} ->
      elapsed = %{plan_selection: plan, simulation: simulation, total: plan + simulation}
      {position, Map.fetch!(elapsed, boundary) + shift}
    end)
  end

  # One reading sequence for three ordered markers per replica. Each replica
  # starts after the previous end, so all readings stay strictly increasing.
  defp readings(durations) do
    {readings, _clock} =
      Enum.map_reduce(durations, 7_000, fn {plan, simulation}, clock ->
        plan_start = clock + 5
        simulation_start = plan_start + plan
        replica_end = simulation_start + simulation

        {{plan_start, simulation_start, replica_end}, replica_end}
      end)

    readings
    |> Enum.flat_map(fn {plan_start, simulation_start, replica_end} ->
      [plan_start, simulation_start, replica_end]
    end)
    |> reading_clock()
  end

  # Each call returns the next programmed reading, so a marker that consumes an
  # extra reading changes the following durations.
  defp reading_clock(readings) do
    {:ok, counter} = Agent.start_link(fn -> readings end)

    fn ->
      Agent.get_and_update(counter, fn
        [reading | rest] -> {reading, rest}
        [] -> {0, []}
      end)
    end
  end

  defp start_service(clock) do
    name = unique_name()
    start_service(name, clock)
    name
  end

  defp start_service(name, clock) do
    id = make_ref()
    start_supervised!(Supervisor.child_spec({Timing, [name: name, clock: clock]}, id: id))
    id
  end

  defp unique_name do
    :"final_timing_#{System.unique_integer([:positive, :monotonic])}"
  end
end
