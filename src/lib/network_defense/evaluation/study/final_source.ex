defmodule NetworkDefense.Evaluation.Study.FinalSource do
  @moduledoc false

  alias NetworkDefense.Evaluation.Family.Contracts.Identity
  alias NetworkDefense.Evaluation.Study.Contracts.{Definition, StudyError}
  alias NetworkDefense.Evaluation.Study.FinalBindingContext

  @enforce_keys [
    :study_revision_id,
    :family_id,
    :candidate_id,
    :plan_count_per_side,
    :attacks_per_plan,
    :pilot_analysis_phase_id,
    :expected_comparisons
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          study_revision_id: Ecto.UUID.t(),
          family_id: String.t(),
          candidate_id: String.t(),
          plan_count_per_side: pos_integer(),
          attacks_per_plan: pos_integer(),
          pilot_analysis_phase_id: Ecto.UUID.t(),
          expected_comparisons: [Identity.t()]
        }

  @spec compare(t(), FinalBindingContext.t()) :: :ok | {:error, StudyError.t()}
  def compare(
        %__MODULE__{} = source,
        %FinalBindingContext{
          execution: execution,
          selection: selection,
          definition: definition,
          accepted_pilot_phase: phase
        }
      ) do
    if source.study_revision_id == execution.study_revision_id and
         source.family_id == definition.family.id and
         source.candidate_id == selection.candidate_id and
         source.plan_count_per_side == selection.plan_count_per_side and
         source.attacks_per_plan == selection.attacks_per_plan and
         source.pilot_analysis_phase_id == phase.id and
         source.expected_comparisons == comparison_identities(definition) do
      :ok
    else
      {:error, StudyError.final_source_mismatch()}
    end
  end

  defp comparison_identities(%Definition{} = definition) do
    Enum.map(definition.family.comparisons, fn comparison ->
      %Identity{
        tier: comparison.tier,
        budget: comparison.budget,
        alternative: Atom.to_string(comparison.alternative),
        reference: Atom.to_string(comparison.reference),
        outcome: comparison.outcome
      }
    end)
  end
end
