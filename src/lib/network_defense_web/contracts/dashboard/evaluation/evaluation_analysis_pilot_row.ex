defmodule NetworkDefenseWeb.Web.Contracts.EvaluationAnalysisPilotRow do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :comparison, :integer
    field :ci_half_width, :float
    field :target, :float
    field :passes, :boolean
    field :paired_attack_seed_count, :integer
    field :approximate_trials, :integer
  end

  @type t :: %__MODULE__{
          comparison: integer(),
          ci_half_width: float() | nil,
          target: float() | nil,
          passes: boolean() | nil,
          paired_attack_seed_count: integer() | nil,
          approximate_trials: integer() | nil
        }
  def changeset(schema, attrs),
    do:
      cast(schema, attrs, [
        :comparison,
        :ci_half_width,
        :target,
        :passes,
        :paired_attack_seed_count,
        :approximate_trials
      ])
end
