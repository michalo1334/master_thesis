defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationAnalysisPilotRow do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :comparison_id, :string
    field :tier, :string
    field :informative, :boolean
    field :candidate_plan_count, :integer
    field :candidate_attacks_per_plan, :integer
    field :guarded_ci_half_width, :float
    field :target, :float
    field :passes, :boolean
  end

  @type t :: %__MODULE__{
          comparison_id: String.t() | nil,
          tier: String.t() | nil,
          informative: boolean() | nil,
          candidate_plan_count: integer() | nil,
          candidate_attacks_per_plan: integer() | nil,
          guarded_ci_half_width: float() | nil,
          target: float() | nil,
          passes: boolean() | nil
        }
  def changeset(schema, attrs),
    do:
      cast(schema, attrs, [
        :comparison_id,
        :tier,
        :informative,
        :candidate_plan_count,
        :candidate_attacks_per_plan,
        :guarded_ci_half_width,
        :target,
        :passes
      ])
end
