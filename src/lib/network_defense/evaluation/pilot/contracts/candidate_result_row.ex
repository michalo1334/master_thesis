defmodule NetworkDefense.Evaluation.Pilot.Contracts.CandidateResultRow do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  # One compact candidate and comparison row. It contains no evidence.

  @type t :: %__MODULE__{
          candidate_position: non_neg_integer(),
          comparison_position: non_neg_integer(),
          plan_count: pos_integer(),
          attacks_per_plan: pos_integer(),
          guarded_half_width: float(),
          informative: boolean(),
          passes: boolean()
        }

  embedded_schema do
    field :candidate_position, :integer
    field :comparison_position, :integer
    field :plan_count, :integer
    field :attacks_per_plan, :integer
    field :guarded_half_width, :float
    field :informative, :boolean
    field :passes, :boolean
  end

  def changeset(row, attrs) do
    cast(row, attrs, [
      :candidate_position,
      :comparison_position,
      :plan_count,
      :attacks_per_plan,
      :guarded_half_width,
      :informative,
      :passes
    ])
  end
end
