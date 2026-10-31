defmodule NetworkDefense.Evaluation2.FinalTierContractTest do
  @moduledoc """
  Strict Gust transport of one Final tier collection run.

  Cases: TIME-01 (measured durations of the five replicas survive the stored
  shape) and BIND-02 (an undecodable terminal result never becomes a tier
  receipt).

  The terminal result crosses the Gust JSON boundary, so every case exercises
  the stored shape: string keys, canonical UUID strings, and JSON scalars. Raw
  clock readings stay in the clock process, so the terminal result carries
  durations only. No case needs the database.
  """

  use ExUnit.Case, async: true
  @moduletag :unit
  @moduletag case_id: "TIME-01/BIND-02"

  alias NetworkDefense.Evaluation2.Study.Final.TierContract
  alias NetworkDefense.Evaluation2.Study.Final.TierContract.{Input, Output}
  alias NetworkDefense.Evaluation2.Study.Final.TierRun
  alias NetworkDefense.Evaluation2.Study.Result.Timing.{Replica, Tier}

  @phase_run_id "5f0d1f7a-3b8f-4c62-9a41-1f2c9b4d7e10"
  @clock_session "4d9c2a6b-7e8f-4a1c-9d3b-5e7f0a2c4e68"

  # Plan-selection and simulation duration of replica positions zero to four.
  @durations for position <- 0..4, do: {120 + 10 * position, 480 + 20 * position}

  describe "Input" do
    test "the canonical input round trips with one phase-run parameter" do
      input = %Input{phase_run_id: @phase_run_id}

      params = TierContract.to_params(input)

      assert params == %{"study_phase_run_id" => @phase_run_id}
      assert {:ok, ^input} = TierContract.decode_input(params)
    end

    test "the input codec rejects extra, missing, and non-canonical values" do
      upper = String.upcase(@phase_run_id)

      for params <- [
            %{},
            %{"study_phase_run_id" => @phase_run_id, "tier" => "small"},
            %{"study_phase_run_id" => upper},
            %{"study_phase_run_id" => "not-a-uuid"},
            %{"study_phase_run_id" => 42},
            %{"study_phase_run_id" => nil},
            %{"study_phase_id" => @phase_run_id},
            [phase_run_id: @phase_run_id]
          ] do
        assert :error = TierContract.decode_input(params)
      end
    end
  end

  describe "Output" do
    test "the measured tier round trips through JSON-safe parameters" do
      output = output()

      assert {:ok, params} = TierContract.encode_output(output)

      assert params == %{
               "study_phase_run_id" => @phase_run_id,
               "tier" => "medium",
               "clock_session" => @clock_session,
               "timing" => %{"replicas" => replica_params()}
             }

      assert {:ok, ^output} = TierContract.decode_output(params)
      assert ^output = TierContract.decode_output!(params)
    end

    test "every declared tier round trips" do
      for {tier, encoded} <- [small: "small", medium: "medium", large: "large"] do
        output = %Output{output() | tier: tier}

        assert {:ok, %{"tier" => ^encoded} = params} = TierContract.encode_output(output)
        assert {:ok, ^output} = TierContract.decode_output(params)
      end
    end

    test "the stored JSON text keeps integer durations" do
      {:ok, params} = TierContract.encode_output(output())

      stored = params |> Jason.encode!() |> Jason.decode!()

      assert {:ok, decoded} = TierContract.decode_output(stored)

      assert decoded.timing.replicas[2] == %Replica{
               plan_selection_us: 140,
               simulation_us: 520,
               total_us: 660
             }
    end

    test "the output codec rejects a value outside the declared shape" do
      valid = output()

      for invalid <- [
            :not_an_output,
            %{},
            %{valid | phase_run_id: "not-a-uuid"},
            %{valid | phase_run_id: String.upcase(@phase_run_id)},
            %{valid | phase_run_id: nil},
            %{valid | tier: :huge},
            %{valid | tier: "small"},
            %{valid | clock_session: ""},
            %{valid | clock_session: nil},
            %{valid | clock_session: 42},
            %{valid | timing: nil},
            %{valid | timing: %Tier{replicas: %{}}},
            %{valid | timing: timing(Map.drop(replicas(), [4]))},
            %{valid | timing: timing(Map.put(replicas(), 5, replica(280, 580)))},
            %{valid | timing: timing(Map.put(replicas(), -1, replica(100, 400)))},
            %{
              valid
              | timing:
                  timing(
                    Map.put(replicas(), 2, %Replica{
                      plan_selection_us: 140,
                      simulation_us: 520,
                      total_us: 661
                    })
                  )
            },
            %{
              valid
              | timing:
                  timing(
                    Map.put(replicas(), 2, %Replica{
                      plan_selection_us: -140,
                      simulation_us: 520,
                      total_us: 380
                    })
                  )
            },
            %{
              valid
              | timing:
                  timing(
                    Map.put(replicas(), 2, %Replica{
                      plan_selection_us: 140.0,
                      simulation_us: 520,
                      total_us: 660.0
                    })
                  )
            },
            %{
              valid
              | timing:
                  timing(
                    Map.put(replicas(), 2, %Replica{
                      plan_selection_us: 140,
                      simulation_us: 520,
                      total_us: 660.0
                    })
                  )
            },
            %{
              valid
              | timing:
                  timing(
                    Map.put(replicas(), 2, %Replica{
                      plan_selection_us: 140,
                      simulation_us: nil,
                      total_us: 660
                    })
                  )
            },
            %{valid | timing: %{replicas: replicas()}}
          ] do
        assert :error = TierContract.encode_output(invalid)
      end
    end

    test "the decoder rejects extra, missing, and former root keys" do
      params = params()

      for invalid <- [
            Map.put(params, "receipt", %{}),
            Map.put(params, "replica_positions", [0, 1, 2, 3, 4]),
            Map.delete(params, "clock_session"),
            Map.delete(params, "tier"),
            Map.delete(params, "study_phase_run_id"),
            Map.drop(params, ["tier", "timing"]),
            %{},
            Map.new(params, fn {key, value} -> {String.to_atom(key), value} end),
            [params]
          ] do
        assert :error = TierContract.decode_output(invalid)
      end
    end

    test "the decoder rejects an invalid phase run, tier, and clock session" do
      for {key, value} <- [
            {"study_phase_run_id", String.upcase(@phase_run_id)},
            {"study_phase_run_id", "not-a-uuid"},
            {"study_phase_run_id", 42},
            {"study_phase_run_id", nil},
            {"tier", "Medium"},
            {"tier", "huge"},
            {"tier", :medium},
            {"tier", 1},
            {"clock_session", ""},
            {"clock_session", nil},
            {"clock_session", 42}
          ] do
        assert :error = TierContract.decode_output(Map.put(params(), key, value))
      end
    end

    test "the decoder rejects an invalid timing block" do
      valid = replica_params()

      for timing <- [
            %{},
            %{"replicas" => Enum.take(valid, 4)},
            %{"replicas" => valid ++ [replica_params(5, 280, 580)]},
            %{"replicas" => List.replace_at(valid, 4, replica_params(0, 280, 580))},
            %{"replicas" => Enum.reverse(valid)},
            %{"replicas" => %{"0" => hd(valid)}},
            %{"replicas" => valid, "warm_up" => replica_params(-1, 100, 400)},
            %{"replicas" => :none}
          ] do
        assert :error = TierContract.decode_output(Map.put(params(), "timing", timing))
      end
    end

    test "the decoder rejects an invalid replica entry" do
      valid = replica_params()

      for entry <- [
            %{},
            Map.delete(hd(valid), "total_us"),
            Map.put(hd(valid), "replicas", []),
            %{hd(valid) | "replica_position" => 5},
            %{hd(valid) | "replica_position" => -1},
            %{hd(valid) | "replica_position" => "0"},
            %{hd(valid) | "plan_selection_us" => "120"},
            %{hd(valid) | "plan_selection_us" => 120.0},
            %{hd(valid) | "simulation_us" => -480},
            %{hd(valid) | "total_us" => 600.0},
            %{hd(valid) | "total_us" => 601},
            Map.delete(hd(valid), "plan_selection_us")
          ] do
        stored = Map.put(params(), "timing", %{"replicas" => [entry | tl(valid)]})
        assert :error = TierContract.decode_output(stored)
      end
    end

    test "the raising decoder rejects a stored value outside the declared shape" do
      assert_raise MatchError, fn -> TierContract.decode_output!(%{}) end
    end
  end

  describe "tier run reconstruction" do
    test "a tier run carries the receipt of its decoded terminal result" do
      {:ok, params} = TierContract.encode_output(output())
      {:ok, decoded} = TierContract.decode_output(params)

      tier_run = TierRun.from_output(7, decoded)

      assert %TierRun{
               gust_run_id: 7,
               tier: :medium,
               phase_run_id: @phase_run_id,
               clock_session: @clock_session,
               timing: %Tier{replicas: replicas}
             } = tier_run

      assert replicas == replicas()
      assert tier_run.gust_run_id == 7
    end
  end

  defp output do
    %Output{
      phase_run_id: @phase_run_id,
      tier: :medium,
      clock_session: @clock_session,
      timing: timing(replicas())
    }
  end

  defp params do
    {:ok, params} = TierContract.encode_output(output())
    params
  end

  defp timing(replicas), do: %Tier{replicas: replicas}

  defp replicas do
    @durations
    |> Enum.with_index()
    |> Map.new(fn {{plan, simulation}, position} -> {position, replica(plan, simulation)} end)
  end

  defp replica(plan, simulation) do
    %Replica{plan_selection_us: plan, simulation_us: simulation, total_us: plan + simulation}
  end

  defp replica_params do
    @durations
    |> Enum.with_index()
    |> Enum.map(fn {{plan, simulation}, position} ->
      replica_params(position, plan, simulation)
    end)
  end

  defp replica_params(position, plan, simulation) do
    %{
      "replica_position" => position,
      "plan_selection_us" => plan,
      "simulation_us" => simulation,
      "total_us" => plan + simulation
    }
  end
end
