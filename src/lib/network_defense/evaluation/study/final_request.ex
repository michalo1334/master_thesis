defmodule NetworkDefense.Evaluation.Study.FinalRequest do
  @moduledoc false

  alias NetworkDefense.Evaluation.Final.Contracts.{FinalError, Request}
  alias NetworkDefense.Evaluation.Study.FinalBindingContext

  @spec build(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Request.t()} | {:error, FinalError.t()}
  def build(execution_id, snapshot_id) do
    with {:ok, context} <- load_context(execution_id),
         %{snapshot_id: ^snapshot_id} = phase <- context.accepted_final_collection_phase do
      request(context, phase, snapshot_id)
    else
      _missing_or_mismatched_snapshot -> lifecycle_error()
    end
  end

  defp load_context(execution_id) do
    case FinalBindingContext.load_for_analysis(execution_id) do
      {:ok, context} -> {:ok, context}
      {:error, _error} -> lifecycle_error()
    end
  end

  defp request(context, phase, snapshot_id) do
    definition = context.definition
    selection = context.selection
    analysis = definition.final.analysis

    %{
      "schema_version" => definition.schema_version,
      "evidence_role" => "final",
      "method" => definition.family.method,
      "family_id" => definition.family.id,
      "study_revision_id" => context.execution.study_revision_id,
      "study_execution_id" => context.execution.id,
      "snapshot_id" => snapshot_id,
      "source_pilot_run_id" => context.accepted_pilot_phase.gust_run_id,
      "plan_count" => selection.plan_count_per_side,
      "attacks_per_plan" => selection.attacks_per_plan,
      "expected_comparisons" => Enum.map(definition.family.comparisons, &comparison_params/1),
      "comparison_seeds" => analysis.comparison_seeds,
      "analysis" => %{
        "alpha" => analysis.alpha,
        "confidence_level" => analysis.confidence_level,
        "test_alternative" => analysis.test_alternative,
        "bootstrap_replicates" => analysis.bootstrap_replicates
      },
      "assertions" => %{
        "final_evidence_collected_after_pilot" => true,
        "pilot_observations_excluded" => true,
        "collection_completed_at" => DateTime.to_iso8601(phase.updated_at)
      }
    }
    |> Request.parse()
  end

  defp comparison_params(comparison) do
    %{
      "tier" => comparison.tier,
      "budget" => comparison.budget,
      "alternative" => Atom.to_string(comparison.alternative),
      "reference" => Atom.to_string(comparison.reference),
      "outcome" => comparison.outcome
    }
  end

  defp lifecycle_error do
    {:error,
     FinalError.changed_pilot_source(
       "The Final request does not match the accepted study lifecycle source."
     )}
  end
end
