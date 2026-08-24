defmodule NetworkDefenseWeb.Web.Contracts.EvaluationAnalysisPrimaryRow do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :comparison, :integer
    field :strategy, :string
    field :baseline, :string
    field :budget, :integer
    field :outcome, :string
    field :paired_mean_difference, :float
    field :ci_lower, :float
    field :ci_upper, :float
    field :ci_half_width, :float
    field :d_z, :float
    field :p_raw, :float
    field :p_adjusted, :float
  end

  @type t :: %__MODULE__{
          comparison: integer(),
          strategy: String.t(),
          baseline: String.t(),
          budget: integer(),
          outcome: String.t(),
          paired_mean_difference: float() | nil,
          ci_lower: float() | nil,
          ci_upper: float() | nil,
          ci_half_width: float() | nil,
          d_z: float() | nil,
          p_raw: float() | nil,
          p_adjusted: float() | nil
        }
  def changeset(schema, attrs),
    do:
      cast(schema, attrs, [
        :comparison,
        :strategy,
        :baseline,
        :budget,
        :outcome,
        :paired_mean_difference,
        :ci_lower,
        :ci_upper,
        :ci_half_width,
        :d_z,
        :p_raw,
        :p_adjusted
      ])
end
