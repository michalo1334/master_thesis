defmodule NetworkDefenseWeb.Web.Contracts.EvaluationAnalysisSecondaryRow do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :comparison, :integer
    field :strategy, :string
    field :baseline, :string
    field :budget, :integer
    field :outcome, :string
    field :mean_difference, :float
    field :ci_lower, :float
    field :ci_upper, :float
    field :ci_half_width, :float
  end

  @type t :: %__MODULE__{
          comparison: integer(),
          strategy: String.t(),
          baseline: String.t(),
          budget: integer(),
          outcome: String.t(),
          mean_difference: float() | nil,
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
        :outcome,
        :mean_difference,
        :ci_lower,
        :ci_upper,
        :ci_half_width
      ])
end
