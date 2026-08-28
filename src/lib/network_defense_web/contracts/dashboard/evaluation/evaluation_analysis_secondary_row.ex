defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationAnalysisSecondaryRow do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefense.Optimization.ModelVariant

  @enum_values model_variant: ModelVariant.wire_values(),
               baseline_model_variant: ModelVariant.wire_values()

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :comparison, :integer
    field :strategy, :string
    field :model_variant, :string
    field :baseline, :string
    field :baseline_model_variant, :string
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
          model_variant: String.t(),
          baseline: String.t(),
          baseline_model_variant: String.t(),
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
        :model_variant,
        :baseline,
        :baseline_model_variant,
        :budget,
        :outcome,
        :mean_difference,
        :ci_lower,
        :ci_upper,
        :ci_half_width
      ])
      |> validate_required([:model_variant, :baseline_model_variant])
      |> validate_inclusion(:model_variant, @enum_values[:model_variant])
      |> validate_inclusion(:baseline_model_variant, @enum_values[:baseline_model_variant])
end
