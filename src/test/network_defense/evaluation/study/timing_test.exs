defmodule NetworkDefense.Evaluation.Study.TimingTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Evaluation.Study.Timing
  alias NetworkDefense.Evaluation.Study.Timing.{Interval, Replica}

  describe "schedule/1" do
    test "TIMING-SCHEDULE-01: emits one warm-up and five measured replicas for one tier" do
      assert Timing.schedule(["bronze"]) == [
               %Replica{tier: "bronze", position: -1, kind: :warm_up},
               %Replica{tier: "bronze", position: 0, kind: :measured},
               %Replica{tier: "bronze", position: 1, kind: :measured},
               %Replica{tier: "bronze", position: 2, kind: :measured},
               %Replica{tier: "bronze", position: 3, kind: :measured},
               %Replica{tier: "bronze", position: 4, kind: :measured}
             ]
    end

    test "TIMING-SCHEDULE-02: completes each tier before emitting the next tier" do
      assert Timing.schedule(["bronze", "silver"]) == [
               %Replica{tier: "bronze", position: -1, kind: :warm_up},
               %Replica{tier: "bronze", position: 0, kind: :measured},
               %Replica{tier: "bronze", position: 1, kind: :measured},
               %Replica{tier: "bronze", position: 2, kind: :measured},
               %Replica{tier: "bronze", position: 3, kind: :measured},
               %Replica{tier: "bronze", position: 4, kind: :measured},
               %Replica{tier: "silver", position: -1, kind: :warm_up},
               %Replica{tier: "silver", position: 0, kind: :measured},
               %Replica{tier: "silver", position: 1, kind: :measured},
               %Replica{tier: "silver", position: 2, kind: :measured},
               %Replica{tier: "silver", position: 3, kind: :measured},
               %Replica{tier: "silver", position: 4, kind: :measured}
             ]
    end

    test "TIMING-SCHEDULE-03: returns an empty list when there are no tiers" do
      assert Timing.schedule([]) == []
    end
  end

  describe "Interval.between/2" do
    test "TIMING-INTERVAL-01: returns a positive elapsed duration" do
      assert {:ok, %Interval{elapsed_us: 250}} = Interval.between(1_000, 1_250)
    end

    test "TIMING-INTERVAL-02: returns zero for equal readings" do
      assert {:ok, %Interval{elapsed_us: 0}} = Interval.between(-100, -100)
    end

    test "TIMING-INTERVAL-03: rejects reversed readings" do
      assert {:error, :invalid_interval} = Interval.between(1_250, 1_000)
    end

    test "TIMING-INTERVAL-04: calculates independent overlapping spans" do
      assert {:ok, %Interval{elapsed_us: plan_elapsed_us}} = Interval.between(100, 250)
      assert {:ok, %Interval{elapsed_us: simulation_elapsed_us}} = Interval.between(200, 500)
      assert {:ok, %Interval{elapsed_us: total_elapsed_us}} = Interval.between(100, 650)

      assert plan_elapsed_us == 150
      assert simulation_elapsed_us == 300
      assert total_elapsed_us == 550
      refute total_elapsed_us == plan_elapsed_us + simulation_elapsed_us
    end
  end
end
