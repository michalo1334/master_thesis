defmodule NetworkDefenseWeb.Web.Contracts.EvaluationAnalysisCapabilityRow do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :comparison, :integer
    field :strategy, :string
    field :baseline, :string
    field :budget, :integer
    field :capability_id, :string
    field :tested_probability, :float
    field :baseline_probability, :float
    field :probability_difference, :float
    field :ci_lower, :float
    field :ci_upper, :float
    field :ci_half_width, :float
  end

  @type t :: %__MODULE__{
          comparison: integer(),
          strategy: String.t(),
          baseline: String.t(),
          budget: integer(),
          capability_id: String.t(),
          tested_probability: float() | nil,
          baseline_probability: float() | nil,
          probability_difference: float() | nil,
          ci_lower: float() | nil,
          ci_upper: float() | nil,
          ci_half_width: float() | nil
        }
  def changeset(schema, attrs),
    do:
      cast(schema, attrs, [
        :comparison,
        :strategy,
        :baseline,
        :budget,
        :capability_id,
        :tested_probability,
        :baseline_probability,
        :probability_difference,
        :ci_lower,
        :ci_upper,
        :ci_half_width
      ])
end
