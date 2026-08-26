defmodule NetworkDefenseWeb.Web.Contracts.EvaluationAnalysisCapabilityRow do
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
    field :capability_id, :string
    field :capability_name, :string
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
          model_variant: String.t(),
          baseline: String.t(),
          baseline_model_variant: String.t(),
          budget: integer(),
          capability_id: String.t(),
          capability_name: String.t() | nil,
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
        :model_variant,
        :baseline,
        :baseline_model_variant,
        :budget,
        :capability_id,
        :capability_name,
        :tested_probability,
        :baseline_probability,
        :probability_difference,
        :ci_lower,
        :ci_upper,
        :ci_half_width
      ])
      |> validate_required([:model_variant, :baseline_model_variant])
      |> validate_inclusion(:model_variant, @enum_values[:model_variant])
      |> validate_inclusion(:baseline_model_variant, @enum_values[:baseline_model_variant])
end
