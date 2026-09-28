defmodule NetworkDefenseWeb.EvaluationAnalysisStudyContractTest do
  use ExUnit.Case, async: true

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationAnalysisMetadata
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationAnalysisPilotRow
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationAnalysisPrimaryRow
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationAnalysisSecondaryRow

  test "casts a study pilot row with every new field" do
    changeset =
      EvaluationAnalysisPilotRow.changeset(%EvaluationAnalysisPilotRow{}, %{
        "comparison_id" => "small|full|simulation_informed|cvss|1|mission_impact",
        "tier" => "small",
        "informative" => true,
        "candidate_plan_count" => 6,
        "candidate_attacks_per_plan" => 12,
        "guarded_ci_half_width" => 0.5,
        "target" => 1.0,
        "passes" => true
      })

    assert changeset.valid?
    assert changeset.changes[:tier] == "small"
    assert changeset.changes[:candidate_plan_count] == 6
    assert changeset.changes[:guarded_ci_half_width] == 0.5
  end

  test "casts a study primary row with tier, comparison ID, and sample counts" do
    changeset =
      EvaluationAnalysisPrimaryRow.changeset(%EvaluationAnalysisPrimaryRow{}, %{
        "comparison" => 0,
        "comparison_id" => "small|full|simulation_informed|cvss|1|mission_impact",
        "tier" => "small",
        "strategy" => "simulation_informed",
        "model_variant" => "full",
        "baseline" => "cvss",
        "baseline_model_variant" => "full",
        "budget" => 1,
        "outcome" => "mission_impact",
        "informative" => false,
        "tested_plan_count" => 6,
        "baseline_plan_count" => 6,
        "attacks_per_plan" => 12
      })

    assert changeset.valid?
    assert changeset.changes[:informative] == false
    assert changeset.changes[:tested_plan_count] == 6
    assert changeset.changes[:baseline_plan_count] == 6
    assert changeset.changes[:attacks_per_plan] == 12
  end

  test "requires the non-null primary and secondary row fields" do
    primary =
      EvaluationAnalysisPrimaryRow.changeset(%EvaluationAnalysisPrimaryRow{}, %{
        "model_variant" => "full",
        "baseline_model_variant" => "full"
      })

    secondary =
      EvaluationAnalysisSecondaryRow.changeset(%EvaluationAnalysisSecondaryRow{}, %{
        "model_variant" => "full",
        "baseline_model_variant" => "full"
      })

    refute primary.valid?
    refute secondary.valid?

    assert %{
             comparison: ["can't be blank"],
             strategy: ["can't be blank"],
             baseline: ["can't be blank"],
             budget: ["can't be blank"],
             outcome: ["can't be blank"]
           } = errors_on(primary)

    assert %{
             comparison: ["can't be blank"],
             strategy: ["can't be blank"],
             baseline: ["can't be blank"],
             budget: ["can't be blank"],
             outcome: ["can't be blank"]
           } = errors_on(secondary)
  end

  test "casts actual study metadata without legacy manifest fields" do
    changeset =
      EvaluationAnalysisMetadata.changeset(%EvaluationAnalysisMetadata{}, %{
        "study_id" => "study-1",
        "specification_version" => 2,
        "command_mode" => "study-pilot",
        "family_scope" => "study",
        "family_size" => 36,
        "tier_labels" => ["small", "medium", "large"],
        "expected_family" => %{"baseline" => "cvss"},
        "uncertainty_sources" => ["plan_selection", "attack_outcome"],
        "recommended_plan_selection_seed_count" => 6,
        "recommended_attacks_per_plan" => 12,
        "insufficient_pilot" => true
      })

    assert changeset.valid?
    assert changeset.changes[:study_id] == "study-1"
    assert changeset.changes[:family_scope] == "study"
    assert changeset.changes[:family_size] == 36
    assert changeset.changes[:insufficient_pilot] == true
    refute Map.has_key?(changeset.changes, :runtime_summary)
  end

  test "casts metadata without study fields" do
    changeset =
      EvaluationAnalysisMetadata.changeset(%EvaluationAnalysisMetadata{}, %{
        "manifest_id" => "manifest",
        "schema_version" => 3,
        "model_version" => "model",
        "command_mode" => "analyze",
        "runtime_summary" => runtime_summary()
      })

    assert changeset.valid?
    refute Map.has_key?(changeset.changes, :family_scope)
    refute Map.has_key?(changeset.changes, :insufficient_pilot)
  end

  test "rejects wrong study field types" do
    pilot =
      EvaluationAnalysisPilotRow.changeset(%EvaluationAnalysisPilotRow{}, %{
        "comparison_id" => "small|full|simulation_informed|cvss|1|mission_impact",
        "tier" => 1,
        "informative" => "yes",
        "candidate_plan_count" => 6.5
      })

    metadata =
      EvaluationAnalysisMetadata.changeset(%EvaluationAnalysisMetadata{}, %{
        "manifest_id" => "study-1",
        "schema_version" => 2,
        "model_version" => "model",
        "command_mode" => "study-pilot",
        "family_scope" => 1,
        "family_size" => "36",
        "insufficient_pilot" => "no"
      })

    refute pilot.valid?
    assert %{tier: ["is invalid"], informative: ["is invalid"]} = errors_on(pilot)

    refute metadata.valid?
    assert %{family_scope: ["is invalid"]} = errors_on(metadata)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end

  defp runtime_summary do
    %{
      "median_plan_selection_runtime_ms" => 1.0,
      "median_simulation_runtime_ms" => 2.0,
      "evaluator_runtime_ms" => 3.0
    }
  end
end
