defmodule NetworkDefense.Evaluation.Study.PilotRequest do
  @moduledoc false

  alias NetworkDefense.Evaluation.Pilot.Contracts.PilotRequest, as: Contract
  alias NetworkDefense.Evaluation.Study.Contracts.Definition
  alias NetworkDefense.Evaluation.Study.Contracts.Definition.{Candidate, Comparison}
  alias NetworkDefense.Evaluation.StudyExecution

  @spec build(StudyExecution.t(), Definition.t(), Ecto.UUID.t()) ::
          {:ok, Contract.t()} | {:error, NetworkDefense.Evaluation.Pilot.Contracts.PilotError.t()}
  def build(
        %StudyExecution{} = execution,
        %Definition{} = definition,
        snapshot_id
      ) do
    analysis = definition.pilot.analysis

    %{
      "schema_version" => 1,
      "evidence_role" => "pilot",
      "method" => "precision_pilot_v1",
      "pilot_id" => execution.id,
      "study_revision_id" => execution.study_revision_id,
      "family_id" => definition.family.id,
      "snapshot_id" => snapshot_id,
      "expected_comparisons" => Enum.map(definition.family.comparisons, &comparison/1),
      "candidates" => Enum.map(definition.pilot.candidates, &candidate/1),
      "pilot_sampling" => %{
        "outer_subsamples" => analysis.outer_subsamples,
        "seed" => analysis.base_seed
      },
      "precision" => %{
        "target_half_width" => analysis.target_half_width,
        "guard_quantile" => analysis.guard_quantile,
        "confidence_level" => analysis.confidence_level,
        "bootstrap_replicates" => analysis.bootstrap_replicates
      },
      "selection" => %{"rule" => analysis.selection_rule}
    }
    |> Contract.parse()
  end

  defp comparison(%Comparison{} = comparison) do
    %{
      "tier" => comparison.tier,
      "budget" => comparison.budget,
      "alternative" => Atom.to_string(comparison.alternative),
      "reference" => Atom.to_string(comparison.reference),
      "outcome" => comparison.outcome
    }
  end

  defp candidate(%Candidate{} = candidate) do
    %{
      "id" => candidate.id,
      "plan_count" => candidate.plan_count_per_side,
      "attacks_per_plan" => candidate.attacks_per_plan
    }
  end
end
