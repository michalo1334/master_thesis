defmodule Mix.Tasks.Study.CommandsTest do
  @moduledoc """
  CMD-02: arguments, application startup, bounded errors, and printed reports of
  the study commands.

  The supported study facade and the shared startup helper are replaced by
  expectations, so the cases cover the command layer only: argument policy,
  startup mode, delegation, and output. A real study belongs to CMD-01.

  Command layers under test:

      mix study.create <file>
      mix study.pilot <study-id> <revision>
      mix study.final <execution-id> --recommended
      mix study.final <execution-id> --override-insufficient <candidate-id>
      mix study.continue <execution-id>
      mix study.status <execution-id>
      mix study.pilot_result <execution-id>
      mix study.result <execution-id>
      mix study.cancel <execution-id>
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Study.{Cancel, Continue, Create, Final, Pilot}
  alias Mix.Tasks.Study.PilotResult, as: PilotResultTask
  alias Mix.Tasks.Study.Result, as: ResultTask
  alias Mix.Tasks.Study.Status, as: StatusTask
  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.Comparison
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.PilotOutcome
  alias NetworkDefense.Evaluation2.Study.PilotResult
  alias NetworkDefense.Evaluation2.Study.PilotResult.Candidate
  alias NetworkDefense.Evaluation2.Study.PilotResult.Comparison, as: PilotComparison
  alias NetworkDefense.Evaluation2.Study.Result
  alias NetworkDefense.Evaluation2.Study.Result.Comparison, as: ResultComparison
  alias NetworkDefense.Evaluation2.Study.Result.Comparison.Adjustment
  alias NetworkDefense.Evaluation2.Study.Result.Comparison.Assessment
  alias NetworkDefense.Evaluation2.Study.Result.Comparison.Estimate
  alias NetworkDefense.Evaluation2.Study.Result.Comparison.Interval
  alias NetworkDefense.Evaluation2.Study.Result.Comparison.Statistics
  alias NetworkDefense.Evaluation2.Study.Result.Comparison.Test
  alias NetworkDefense.Evaluation2.Study.Result.Family
  alias NetworkDefense.Evaluation2.Study.Result.Timing
  alias NetworkDefense.Evaluation2.Study.Result.Timing.Replica
  alias NetworkDefense.Evaluation2.Study.Result.Timing.Tier, as: TimingTier
  alias NetworkDefense.Evaluation2.Study.Revision
  alias NetworkDefense.Evaluation2.Study.Selection
  alias NetworkDefense.Evaluation2.Study.Status, as: StudyStatus
  alias NetworkDefense.Evaluation2.Study.Tier

  @execution_id "0f0f0f0f-0000-4000-8000-000000000000"
  @identity %Revision{study_id: "example-study", revision: 1}

  setup do
    :meck.new(Mix.Study.Command, [:passthrough, :no_link])
    :meck.new(Study, [:no_link])
    parent = self()

    :meck.expect(Mix.Study.Command, :start!, fn mode ->
      send(parent, {:start!, mode})
      :ok
    end)

    on_exit(fn ->
      :meck.unload(Mix.Study.Command)
      :meck.unload(Study)
    end)

    :ok
  end

  describe "argument policy" do
    test "every command rejects malformed arguments before it starts the application" do
      for {task, args} <- [
            {Create, []},
            {Create, ["a.yaml", "b.yaml"]},
            {Pilot, []},
            {Pilot, ["example-study"]},
            {Pilot, ["example-study", "zero"]},
            {Pilot, ["example-study", "0"]},
            {Final, [@execution_id]},
            {Final, [@execution_id, "--recommended", "--override-insufficient", "c2"]},
            {Final, [@execution_id, "--recommended", "--recommended"]},
            {Final, [@execution_id, "--recommended", "--no-recommended"]},
            {Final,
             [@execution_id, "--override-insufficient", "c2", "--override-insufficient", "c3"]},
            {Final, [@execution_id, "--override-insufficient"]},
            {Final, [@execution_id, "--unexpected"]},
            {Final, ["--recommended"]},
            {Continue, []},
            {StatusTask, []},
            {PilotResultTask, []},
            {ResultTask, []},
            {Cancel, []}
          ] do
        error = assert_raise Mix.Error, ~r/Usage: mix study\./, fn -> task.run(args) end
        assert error.message =~ "Usage: mix study."
      end

      refute_received {:start!, _mode}
    end
  end

  describe "revision creation" do
    test "create freezes one revision in the inspecting role and prints its identity" do
      path = write_definition!()

      :meck.expect(Study, :create_revision, fn document ->
        assert document == "study_id: example-study\nrevision: 1\n"
        {:ok, @identity}
      end)

      output = capture_io(fn -> assert :ok = Create.run([path]) end)

      assert_received {:start!, :inspect}
      assert output =~ "Study: example-study"
      assert output =~ "Revision: 1"
    end

    test "create refuses a missing file before it starts the application" do
      path = Path.join(System.tmp_dir!(), "missing-study-definition.yaml")

      error = assert_raise Mix.Error, ~r/Cannot read/, fn -> Create.run([path]) end

      assert error.message =~ path
      refute_received {:start!, _mode}
    end
  end

  describe "pilot" do
    test "pilot starts the declared revision, waits, and prints the Pilot report" do
      :meck.expect(Study, :start, fn revision ->
        assert revision == %Revision{study_id: "example-study", revision: 3}
        {:ok, status(:collecting_pilot)}
      end)

      :meck.expect(Study, :continue, fn @execution_id -> {:ok, awaiting_final()} end)
      :meck.expect(Study, :pilot_result, fn @execution_id -> {:ok, pilot_report()} end)

      output = capture_io(fn -> assert :ok = Pilot.run(["example-study", "3"]) end)

      assert_received {:start!, :execute}
      assert output =~ "Execution: #{@execution_id}"
      assert output =~ "State: awaiting_final"
      assert output =~ "Pilot report"
      assert output =~ "Candidate c2: 6 plans per side, 5 attacks per plan"
      assert output =~ "small budget 4 cvss vs null mission_impact"
    end

    test "pilot prints the committed identifier before a failed continuation" do
      :meck.expect(Study, :start, fn _revision -> {:ok, status(:collecting_pilot)} end)

      :meck.expect(Study, :continue, fn @execution_id ->
        IO.puts("Continuation entered")
        {:error, error()}
      end)

      output =
        capture_io(fn ->
          assert_raise Mix.Error, "study pilot failed", fn ->
            Pilot.run(["example-study", "1"])
          end
        end)

      assert String.starts_with?(output, "Execution: #{@execution_id}\nContinuation entered\n")
    end

    test "pilot fails when the execution stops before the approval boundary" do
      :meck.expect(Study, :start, fn _revision -> {:ok, status(:collecting_pilot)} end)
      :meck.expect(Study, :continue, fn @execution_id -> {:ok, failed()} end)

      output =
        capture_io(fn ->
          assert_raise Mix.Error, "study pilot failed", fn ->
            Pilot.run(["example-study", "1"])
          end
        end)

      assert output =~ "State: failed"
    end
  end

  describe "final" do
    test "final approves the recommendation, waits for success, and prints the result" do
      :meck.expect(Study, :resume, fn @execution_id, :recommended ->
        {:ok, status(:collecting_final)}
      end)

      :meck.expect(Study, :continue, fn @execution_id -> {:ok, succeeded()} end)
      :meck.expect(Study, :result, fn @execution_id -> {:ok, result()} end)

      output =
        capture_io(fn -> assert :ok = Final.run([@execution_id, "--recommended"]) end)

      assert_received {:start!, :execute}
      assert output =~ "State: succeeded"
      assert output =~ "Family: primary"
      assert output =~ "adjusted p-value 0.004"
      assert output =~ "Timing (median of five measured replicas)"
    end

    test "final carries an explicit insufficient override" do
      :meck.expect(Study, :resume, fn @execution_id, approval ->
        assert approval == {:override_insufficient, "c2"}
        {:ok, status(:collecting_final)}
      end)

      :meck.expect(Study, :continue, fn @execution_id -> {:ok, succeeded()} end)
      :meck.expect(Study, :result, fn @execution_id -> {:ok, result()} end)

      capture_io(fn ->
        assert :ok = Final.run([@execution_id, "--override-insufficient", "c2"])
      end)
    end

    test "final fails when the execution stops before success" do
      :meck.expect(Study, :resume, fn @execution_id, :recommended ->
        {:ok, status(:collecting_final)}
      end)

      :meck.expect(Study, :continue, fn @execution_id -> {:ok, status(:collecting_final)} end)

      capture_io(fn ->
        assert_raise Mix.Error, "study final failed", fn ->
          Final.run([@execution_id, "--recommended"])
        end
      end)
    end
  end

  describe "lifecycle reads and cancel" do
    test "continue waits for the boundary and prints the refreshed status" do
      :meck.expect(Study, :continue, fn @execution_id -> {:ok, awaiting_final()} end)

      output = capture_io(fn -> assert :ok = Continue.run([@execution_id]) end)

      assert_received {:start!, :execute}
      assert output =~ "State: awaiting_final"
      assert output =~ "Pilot outcome: recommended candidate c2"
    end

    test "continue fails on a failed execution" do
      :meck.expect(Study, :continue, fn @execution_id -> {:ok, failed()} end)

      output =
        capture_io(fn ->
          assert_raise Mix.Error, "study continue failed", fn ->
            Continue.run([@execution_id])
          end
        end)

      assert output =~ "State: failed"
      assert output =~ "storage_unavailable"
    end

    test "status reads one execution in the inspecting role" do
      :meck.expect(Study, :status, fn @execution_id -> {:ok, awaiting_final()} end)

      output = capture_io(fn -> assert :ok = StatusTask.run([@execution_id]) end)

      assert_received {:start!, :inspect}
      assert output =~ "Execution: #{@execution_id}"
      assert output =~ "Study: example-study"
      assert output =~ "Revision: 1"
      assert output =~ "State: awaiting_final"
    end

    test "pilot_result prints the complete Pilot report in the inspecting role" do
      :meck.expect(Study, :pilot_result, fn @execution_id -> {:ok, pilot_report()} end)

      output = capture_io(fn -> assert :ok = PilotResultTask.run([@execution_id]) end)

      assert_received {:start!, :inspect}
      assert output =~ "Method: precision_pilot_v1"
      assert output =~ "Selection rule: lowest_predicted_runtime"
      assert output =~ "worst guarded half-width 0.125"
    end

    test "result prints the corrected family in the inspecting role" do
      :meck.expect(Study, :result, fn @execution_id -> {:ok, result()} end)

      output = capture_io(fn -> assert :ok = ResultTask.run([@execution_id]) end)

      assert_received {:start!, :inspect}
      assert output =~ "Method: holm"
      assert output =~ "Alpha: 0.05"
      assert output =~ "reject null: true"
      assert output =~ "small: plan selection 1002 us"
    end

    test "cancel commits the lifecycle change in the non-executing role" do
      :meck.expect(Study, :cancel, fn @execution_id -> {:ok, status(:cancelled)} end)

      output = capture_io(fn -> assert :ok = Cancel.run([@execution_id]) end)

      assert_received {:start!, :inspect}
      refute_received {:start!, :execute}
      assert output =~ "State: cancelled"
    end
  end

  test "a bounded study error prints its issues and fails the command" do
    :meck.expect(Study, :status, fn @execution_id -> {:error, error()} end)

    output =
      capture_io(:stderr, fn ->
        assert_raise Mix.Error, "study status failed", fn ->
          StatusTask.run([@execution_id])
        end
      end)

    assert output =~ "storage_unavailable"
    assert output =~ "The study storage is unavailable."
  end

  defp write_definition! do
    path =
      Path.join(
        System.tmp_dir!(),
        "study-command-#{System.unique_integer([:positive])}.yaml"
      )

    File.write!(path, "study_id: example-study\nrevision: 1\n")
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp status(state, fields \\ []) do
    struct(
      %StudyStatus{
        execution_id: @execution_id,
        revision: @identity,
        state: state,
        pilot_outcome: nil,
        selection: nil,
        error: nil
      },
      fields
    )
  end

  defp awaiting_final, do: status(:awaiting_final, pilot_outcome: outcome())

  defp succeeded,
    do: status(:succeeded, pilot_outcome: outcome(), selection: selection())

  defp failed, do: status(:failed, error: error())

  defp outcome do
    %PilotOutcome{
      outcome: :recommended,
      candidate_id: "c2",
      plan_count_per_side: 6,
      attacks_per_plan: 5
    }
  end

  defp selection do
    %Selection{candidate_id: "c2", plan_count_per_side: 6, attacks_per_plan: 5}
  end

  defp error do
    %Error{
      category: :unavailable,
      issues: [
        %Error.Issue{
          code: "storage_unavailable",
          path: [],
          message: "The study storage is unavailable."
        }
      ]
    }
  end

  defp pilot_report do
    assessment = %PilotComparison{
      identity: comparison_identity(),
      guarded_half_width: 0.125,
      informative: true,
      passes: true
    }

    candidate = %Candidate{
      id: "c2",
      plan_count_per_side: 6,
      attacks_per_plan: 5,
      predicted_runtime_ms: 1200.5,
      comparisons: [assessment]
    }

    %PilotResult{
      method: :precision_pilot_v1,
      selection_rule: :lowest_predicted_runtime,
      outcome: outcome(),
      candidates: [candidate]
    }
  end

  defp result do
    %Result{
      execution_id: @execution_id,
      revision: @identity,
      pilot_outcome: outcome(),
      selection: selection(),
      family: %Family{
        id: "primary",
        method: :holm,
        alpha: 0.05,
        comparisons: [result_comparison()]
      },
      timing: %Timing{by_tier: timing_by_tier()}
    }
  end

  defp result_comparison do
    %ResultComparison{
      identity: comparison_identity(),
      statistics: %Statistics{
        method: :matching_bounded_mean_v1,
        estimate: %Estimate{contrast: :alternative_minus_reference, value: 0.25},
        interval: %Interval{confidence_level: 0.95, lower: 0.1, upper: 0.4},
        test: %Test{
          method: :sign_conservative_betting,
          alternative: :two_sided,
          raw_p_value: 0.004
        },
        assessment: %Assessment{status: :informative, warnings: []}
      },
      adjustment: %Adjustment{adjusted_p_value: 0.004, reject_null: true}
    }
  end

  defp comparison_identity do
    %Comparison{
      tier: :small,
      budget: 4,
      alternative: :cvss,
      reference: :null,
      outcome: "mission_impact"
    }
  end

  defp timing_by_tier do
    replicas =
      Map.new(0..4, fn position ->
        {position,
         %Replica{
           plan_selection_us: 1000 + position,
           simulation_us: 2000 + position,
           total_us: 3000 + position
         }}
      end)

    Map.new(Tier.all(), fn tier -> {tier, %TimingTier{replicas: replicas}} end)
  end
end
