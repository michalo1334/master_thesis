defmodule NetworkDefenseWeb.EvaluationAnalysisPhase1SummaryTest do
  use ExUnit.Case, async: true

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationAnalysisFeasibilityRow
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationAnalysisRuntimeSummary

  test "casts a feasibility row" do
    changeset =
      EvaluationAnalysisFeasibilityRow.changeset(%EvaluationAnalysisFeasibilityRow{}, %{
        "experiment_id" => "experiment",
        "plan_id" => "plan",
        "pre_attack_feasible" => true,
        "unavailable_required_flow_count" => 0,
        "affected_capability_count" => 0
      })

    assert changeset.valid?
  end

  test "casts a baseline feasibility row" do
    changeset =
      EvaluationAnalysisFeasibilityRow.changeset(%EvaluationAnalysisFeasibilityRow{}, %{
        "experiment_id" => "baseline-experiment",
        "plan_id" => "",
        "pre_attack_feasible" => true,
        "unavailable_required_flow_count" => 0,
        "affected_capability_count" => 0
      })

    assert changeset.valid?
  end

  test "rejects incomplete or negative Phase 1 summaries" do
    feasibility =
      EvaluationAnalysisFeasibilityRow.changeset(%EvaluationAnalysisFeasibilityRow{}, %{
        "experiment_id" => "experiment",
        "plan_id" => "plan",
        "pre_attack_feasible" => true,
        "unavailable_required_flow_count" => -1,
        "affected_capability_count" => 0
      })

    runtime =
      EvaluationAnalysisRuntimeSummary.changeset(%EvaluationAnalysisRuntimeSummary{}, %{
        "median_plan_selection_runtime_ms" => 1.0,
        "median_simulation_runtime_ms" => 2.0
      })

    refute feasibility.valid?
    refute runtime.valid?
  end
end
