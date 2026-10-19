defmodule NetworkDefense.Evaluation.Pilot.Contracts.CandidateSummary do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  # One candidate summary. Non-informative comparison positions stay visible
  # even when the candidate is not recommended.

  @type t :: %__MODULE__{
          candidate_position: non_neg_integer(),
          plan_count: pos_integer(),
          attacks_per_plan: pos_integer(),
          worst_guarded_half_width: float(),
          all_comparisons_informative: boolean(),
          non_informative_comparison_positions: [non_neg_integer()],
          all_comparisons_passed: boolean(),
          predicted_runtime_ms: float()
        }

  embedded_schema do
    field :candidate_position, :integer
    field :plan_count, :integer
    field :attacks_per_plan, :integer
    field :worst_guarded_half_width, :float
    field :all_comparisons_informative, :boolean
    field :non_informative_comparison_positions, {:array, :integer}
    field :all_comparisons_passed, :boolean
    field :predicted_runtime_ms, :float
  end

  def changeset(summary, attrs) do
    cast(summary, attrs, [
      :candidate_position,
      :plan_count,
      :attacks_per_plan,
      :worst_guarded_half_width,
      :all_comparisons_informative,
      :non_informative_comparison_positions,
      :all_comparisons_passed,
      :predicted_runtime_ms
    ])
  end
end
