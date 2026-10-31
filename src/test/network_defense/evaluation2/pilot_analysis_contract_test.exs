defmodule NetworkDefense.Evaluation2.PilotAnalysisContractTest do
  @moduledoc """
  Strict Gust transport of the Pilot analysis phase.

  Cases: PILOT-01 (fan-in of every declared assessment) and BIND-02 (rejection of
  an undecodable completion payload).

  The transport crosses the Gust JSON boundary, so every case exercises the
  stored shape: string keys, canonical UUID strings, and JSON scalar types. The
  cases need no database, because codecs and DAG wiring are the whole subject.
  """

  use ExUnit.Case, async: true
  @moduletag :unit
  @moduletag case_id: "PILOT-01/BIND-02"

  alias Gust.DAG.Definition
  alias Gust.DAG.Folder
  alias Gust.DAG.Parser.Adapters.Elixir, as: ElixirParser
  alias NetworkDefense.Evaluation2.Study.Pilot.AnalysisContract
  alias NetworkDefense.Evaluation2.Study.Pilot.AnalysisContract.{Input, Output}
  alias NetworkDefense.Evaluation2.Study.Pilot.{Assessment, Job, Summary}
  alias NetworkDefense.Evaluation2.Study.PilotOutcome
  alias NetworkDefense.Evaluation2.Study.Workflow.PilotAnalysis.Actions.Boundary

  @phase_run_id "9be1c5d2-3f24-4a51-9a9b-0d3bf5cc0f4e"
  @snapshot_id "1ac0d6f0-6e5c-4d2f-8f18-2b7a6e0b5c11"

  describe "Input" do
    test "the canonical input round trips through JSON-safe parameters" do
      input = %Input{phase_run_id: @phase_run_id, snapshot_id: @snapshot_id}

      params = AnalysisContract.to_params(input)

      assert params == %{
               "study_phase_run_id" => @phase_run_id,
               "study_evidence_snapshot_id" => @snapshot_id
             }

      assert {:ok, ^input} = AnalysisContract.decode_input(params)
    end

    test "the input codec rejects non-canonical, missing, and former parameters" do
      upper = String.upcase(@snapshot_id)

      for params <- [
            %{},
            %{"study_phase_run_id" => @phase_run_id},
            %{"study_evidence_snapshot_id" => @snapshot_id},
            %{"study_phase_run_id" => @phase_run_id, "study_evidence_snapshot_id" => upper},
            %{"study_phase_run_id" => "not-a-uuid", "study_evidence_snapshot_id" => @snapshot_id},
            %{"study_phase_run_id" => @phase_run_id, "study_evidence_snapshot_id" => 42},
            %{"study_phase_id" => @phase_run_id, "snapshot_id" => @snapshot_id},
            []
          ] do
        assert :error = AnalysisContract.decode_input(params)
      end
    end
  end

  describe "Output" do
    test "a recommendation round trips with every candidate summary" do
      output = %Output{outcome: recommended(), candidates: [summary(0, true), summary(1, false)]}

      assert {:ok, params} = AnalysisContract.encode_output(output)
      assert {:ok, ^output} = AnalysisContract.decode_output(params)
      assert ^output = AnalysisContract.decode_output!(params)
      assert params["outcome"]["outcome"] == "recommended"
      assert Enum.map(params["candidates"], & &1["candidate_position"]) == [0, 1]
    end

    test "an insufficient outcome round trips without a candidate" do
      output = %Output{
        outcome: %PilotOutcome{outcome: :insufficient},
        candidates: [summary(0, false)]
      }

      assert {:ok, params} = AnalysisContract.encode_output(output)
      assert {:ok, ^output} = AnalysisContract.decode_output(params)
      assert params["outcome"]["candidate_id"] == nil
    end

    test "the output codec rejects the former format and inconsistent outcomes" do
      former = %{"outcome" => "recommended", "candidate_summaries" => []}
      assert :error = AnalysisContract.decode_output(former)

      missing_summaries = %{"outcome" => encode_outcome(recommended())}
      assert :error = AnalysisContract.decode_output(missing_summaries)

      for outcome <- [
            %{"outcome" => "recommended"},
            %{
              "outcome" => "recommended",
              "candidate_id" => nil,
              "plan_count_per_side" => nil,
              "attacks_per_plan" => nil
            },
            %{
              "outcome" => "insufficient",
              "candidate_id" => "small",
              "plan_count_per_side" => 3,
              "attacks_per_plan" => 2
            },
            %{
              "outcome" => "unknown",
              "candidate_id" => nil,
              "plan_count_per_side" => nil,
              "attacks_per_plan" => nil
            }
          ] do
        assert :error =
                 AnalysisContract.decode_output(%{"outcome" => outcome, "candidates" => []})
      end

      for candidates <- [
            [%{}],
            [Map.delete(encode_summary(summary(0, true)), "predicted_runtime_ms")],
            [%{encode_summary(summary(0, true)) | "plan_count_per_side" => 0}],
            [%{encode_summary(summary(0, true)) | "comparisons" => :none}]
          ] do
        assert :error =
                 AnalysisContract.decode_output(%{
                   "outcome" => encode_outcome(%PilotOutcome{outcome: :insufficient}),
                   "candidates" => candidates
                 })
      end
    end
  end

  describe "mapped task transport" do
    test "a job round trips through the mapped task parameters" do
      job = %Job{candidate_position: 2, comparison_position: 1, stream_seed: 987_654_321}
      params = Boundary.job_to_params(job)

      assert params == %{
               "candidate_position" => 2,
               "comparison_position" => 1,
               "stream_seed" => 987_654_321
             }

      assert {:ok, ^job} = Boundary.decode_job(params)
    end

    test "an assessment round trips through the stored task result" do
      assessment = %Assessment{
        candidate_position: 2,
        comparison_position: 1,
        guarded_half_width: 0.125,
        informative: true,
        passes: false
      }

      params = Boundary.assessment_to_params(assessment)
      assert {:ok, ^assessment} = Boundary.decode_assessment(params)
    end

    test "the job and assessment codecs reject foreign shapes" do
      assert :error = Boundary.decode_job(%{"candidate_position" => 0})
      assert :error = Boundary.decode_job(%{"candidate_position" => -1} |> with_job_fields())

      assert :error =
               Boundary.decode_job(Boundary.job_to_params(job()) |> Map.put("stream_seed", -1))

      for overrides <- [
            %{"informative" => "true"},
            %{"passes" => 1},
            %{"guarded_half_width" => "0.1"},
            %{"comparison_position" => -1}
          ] do
        params = Map.merge(Boundary.assessment_to_params(assessment()), overrides)
        assert :error = Boundary.decode_assessment(params)
      end
    end
  end

  describe "DAG" do
    test "the Pilot analysis DAG plans jobs once, maps one evaluation per job, and fans in" do
      {:ok, definition} = ElixirParser.parse_file(dag_path())

      assert Definition.empty_errors?(definition)
      assert Folder.dag_name(dag_path()) == "evaluation2_study_pilot_analysis"

      assert definition.stages == [
               ["prepare_pilot_analysis"],
               ["evaluate_pilot_candidate"],
               ["select_pilot_outcome"]
             ]

      assert %{store_result: true, map_over: nil, downstream: prepared_downstream} =
               definition.tasks["prepare_pilot_analysis"]

      assert MapSet.equal?(prepared_downstream, MapSet.new(["evaluate_pilot_candidate"]))

      assert %{
               store_result: true,
               map_over: :prepare_pilot_analysis,
               downstream: evaluated_downstream
             } =
               definition.tasks["evaluate_pilot_candidate"]

      assert MapSet.equal?(evaluated_downstream, MapSet.new(["select_pilot_outcome"]))

      assert %{store_result: true, downstream: selected_downstream} =
               definition.tasks["select_pilot_outcome"]

      assert MapSet.size(selected_downstream) == 0
    end
  end

  # The checked-in DAG source is the Gust input; the loader names it by file.
  defp dag_path do
    Application.fetch_env!(:gust, :dags_folder)
    |> Path.join("evaluation2_study_pilot_analysis.exs")
  end

  defp recommended do
    %PilotOutcome{
      outcome: :recommended,
      candidate_id: "medium",
      plan_count_per_side: 3,
      attacks_per_plan: 2
    }
  end

  defp job do
    %Job{candidate_position: 0, comparison_position: 0, stream_seed: 1}
  end

  defp assessment do
    %Assessment{
      candidate_position: 0,
      comparison_position: 0,
      guarded_half_width: 0.1,
      informative: true,
      passes: true
    }
  end

  defp with_job_fields(params) do
    Map.merge(
      %{"candidate_position" => 0, "comparison_position" => 0, "stream_seed" => 1},
      params
    )
  end

  # One candidate of the Pilot grid: a sample-size choice, never a tier.
  defp summary(position, passing?) do
    %Summary{
      candidate_position: position,
      candidate_id: "candidate-#{position}",
      plan_count_per_side: position + 3,
      attacks_per_plan: 2,
      predicted_runtime_ms: 1_200 + position,
      comparisons: [
        %Summary.Comparison{
          comparison_position: 0,
          guarded_half_width: 0.1 + position,
          informative: true,
          passes: passing?
        },
        %Summary.Comparison{
          comparison_position: 1,
          guarded_half_width: 0.2 + position,
          informative: passing?,
          passes: passing?
        }
      ]
    }
  end

  defp encode_outcome(outcome) do
    {:ok, encoded} =
      AnalysisContract.encode_output(%Output{outcome: outcome, candidates: []})

    encoded["outcome"]
  end

  defp encode_summary(summary) do
    {:ok, %{"candidates" => [encoded]}} =
      AnalysisContract.encode_output(%Output{
        outcome: %PilotOutcome{outcome: :insufficient},
        candidates: [summary]
      })

    encoded
  end
end
