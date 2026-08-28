defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationPlanSummary do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefense.Optimization.ModelVariant

  @enum_values model_variant: ModelVariant.wire_values()

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :id, :string
    field :model_variant, :string
    field :strategy, :string
    field :requested_budget, :integer
    field :selection_seed, :integer
    field :used_budget, :integer
    field :action_count, :integer
    field :status, :string
  end

  @type t :: %__MODULE__{
          id: String.t(),
          model_variant: String.t(),
          strategy: String.t(),
          requested_budget: integer(),
          selection_seed: integer(),
          used_budget: integer(),
          action_count: integer(),
          status: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :id,
      :model_variant,
      :strategy,
      :requested_budget,
      :selection_seed,
      :used_budget,
      :action_count,
      :status
    ])
    |> validate_required([
      :id,
      :model_variant,
      :strategy,
      :requested_budget,
      :selection_seed,
      :status
    ])
    |> NetworkDefense.Contracts.validate_uuid(:id)
    |> validate_inclusion(:model_variant, @enum_values[:model_variant])
    |> validate_inclusion(:status, ["running", "completed", "failed"])
  end
end
