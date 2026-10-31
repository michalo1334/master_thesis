defmodule NetworkDefense.Evaluation2.FinalAnalysisActionsTest do
  @moduledoc """
  Transport and binding rules of the Final analysis tasks.

  The cases cover the mapped comparison job, the stored evaluation result, the
  declared comparison order of the fan-in batch, and the permanent failure of a
  task that cannot bind its run. They need no database, no Gust run, and no
  scientific computation.

      mix test test/network_defense/evaluation2/final_analysis_actions_test.exs
  """

  use ExUnit.Case, async: false

  @moduletag :unit
  @moduletag case_id: "RESULT-02/BIND-02"

  alias NetworkDefense.Evaluation2.Study.Final.AnalysisContract.Input
  alias NetworkDefense.Evaluation2.Study.Final.ComparisonJob

  alias NetworkDefense.Evaluation2.Study.Result.Comparison.{
    Assessment,
    Estimate,
    Interval,
    Statistics,
    Test
  }

  alias NetworkDefense.Evaluation2.Study.Workflow.FinalAnalysis.Actions.{
    Boundary,
    Correct,
    Evaluate,
    Prepare
  }

  describe "mapped comparison job" do
    test "round trips through the mapped task parameters" do
      job = %ComparisonJob{comparison_position: 2}

      assert Boundary.job_to_params(job) == %{"comparison_position" => 2}
      assert {:ok, ^job} = Boundary.decode_job(%{"comparison_position" => 2})
    end

    test "rejects a job without one declared comparison position" do
      assert Boundary.run_job(%{"comparison_position" => 0}) ==
               {:ok, %ComparisonJob{comparison_position: 0}}

      assert Boundary.run_job(%{}) == {:error, :invalid_job}
      assert Boundary.run_job(%{"comparison_position" => -1}) == {:error, :invalid_job}
      assert Boundary.run_job(%{"comparison_position" => "0"}) == {:error, :invalid_job}

      assert Boundary.run_job(%{"comparison_position" => 0, "unexpected" => 1}) ==
               {:error, :invalid_job}

      assert Boundary.run_job(:invalid) == {:error, :invalid_job}
    end

    test "the prepared batch becomes the mapped task parameters in order" do
      batch = [%ComparisonJob{comparison_position: 0}, %ComparisonJob{comparison_position: 1}]

      assert Boundary.job_params(batch) ==
               {:ok, [%{"comparison_position" => 0}, %{"comparison_position" => 1}]}

      assert {:error, :invalid_jobs} = Boundary.job_params([])
      assert {:error, :invalid_jobs} = Boundary.job_params([%{}])

      assert {:error, :invalid_jobs} =
               Boundary.job_params([%ComparisonJob{comparison_position: -1}])

      assert {:error, :invalid_jobs} = Boundary.job_params(:invalid)
    end
  end

  describe "stored evaluation result" do
    test "round trips one statistics value next to its comparison position" do
      job = %ComparisonJob{comparison_position: 1}
      {:ok, params} = Boundary.evaluation_params(job, statistics(1))

      assert params["comparison_position"] == 1
      assert {:ok, {1, %Statistics{} = decoded}} = Boundary.decode_evaluation(params)
      assert decoded == statistics(1)
    end

    test "rejects a result without a usable position or statistics value" do
      {:ok, valid} =
        Boundary.evaluation_params(%ComparisonJob{comparison_position: 0}, statistics(0))

      for update <- [
            &Map.delete(&1, "comparison_position"),
            &Map.delete(&1, "statistics"),
            &Map.put(&1, "comparison_position", -1),
            &Map.put(&1, "comparison_position", nil),
            &Map.put(&1, "statistics", %{}),
            &Map.put(&1, "unexpected", 1)
          ] do
        assert :error = Boundary.decode_evaluation(update.(valid))
      end

      assert :error = Boundary.decode_evaluation(:invalid)
    end

    test "rejects an evaluation result that the stored shape cannot carry" do
      job = %ComparisonJob{comparison_position: 0}

      assert :error = Boundary.evaluation_params(job, %{statistics(0) | method: :unknown_method})
      assert :error = Boundary.evaluation_params(job, :invalid)
    end

    test "the fan-in batch follows the declared comparison order" do
      batch = [evaluation(2, 2), evaluation(0, 0), evaluation(1, 1)]

      assert {:ok, statistics} = Boundary.evaluations(batch)
      assert statistics == [statistics(0), statistics(1), statistics(2)]
    end

    test "a gap, a repeat, or an unusable entry rejects the whole batch" do
      for batch <- [
            [],
            [evaluation(0, 0), evaluation(2, 2)],
            [evaluation(0, 0), evaluation(0, 1)],
            [evaluation(0, 0), evaluation(1, 1), evaluation(1, 2)],
            [evaluation(0, 0), %{}],
            [evaluation(0, 0), :invalid],
            [evaluation(1, 0)]
          ] do
        assert Boundary.evaluations(batch) == {:error, :incomplete_evaluations}
      end
    end
  end

  describe "run binding" do
    test "rejects an input that does not name one phase run and one snapshot" do
      assert Boundary.run_context(%{}, %{run_id: 1}) == {:error, :invalid_input}

      assert Boundary.run_context(
               %{"study_phase_run_id" => "not-a-uuid", "study_evidence_snapshot_id" => "x"},
               %{run_id: 1}
             ) == {:error, :invalid_input}

      assert Boundary.input(%{
               "study_phase_run_id" => "9be1c5d2-3f24-4a51-9a9b-0d3bf5cc0f4e",
               "study_evidence_snapshot_id" => "1ac0d6f0-6e5c-4d2f-8f18-2b7a6e0b5c11"
             }) ==
               {:ok,
                %Input{
                  phase_run_id: "9be1c5d2-3f24-4a51-9a9b-0d3bf5cc0f4e",
                  snapshot_id: "1ac0d6f0-6e5c-4d2f-8f18-2b7a6e0b5c11"
                }}
    end

    test "every analysis task fails permanently without a usable run input" do
      action_context = %{run_id: 1}

      assert_raise Gust.DAG.NonRecError, fn -> Prepare.execute([params: %{}], action_context) end

      assert_raise Gust.DAG.NonRecError, fn ->
        Evaluate.execute([params: %{}, job: %{"comparison_position" => 0}], action_context)
      end

      assert_raise Gust.DAG.NonRecError, fn -> Correct.execute([params: %{}], action_context) end
    end
  end

  defp evaluation(position, statistics_position) do
    {:ok, params} =
      Boundary.evaluation_params(
        %ComparisonJob{comparison_position: position},
        statistics(statistics_position)
      )

    params
  end

  # One stored evaluation result. The values illustrate the transport shape; the
  # scientific content belongs to the analysis capability.
  defp statistics(position) do
    %Statistics{
      method: :matching_bounded_mean_v1,
      estimate: %Estimate{contrast: :alternative_minus_reference, value: 0.2 + position},
      interval: %Interval{
        confidence_level: 0.95,
        lower: 0.05 + position,
        upper: 0.4 + position
      },
      test: %Test{
        method: :sign_conservative_betting,
        alternative: :two_sided,
        raw_p_value: 0.04 + position / 100
      },
      assessment: %Assessment{status: :informative, warnings: []}
    }
  end
end
