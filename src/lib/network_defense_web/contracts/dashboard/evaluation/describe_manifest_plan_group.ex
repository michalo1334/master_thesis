defmodule NetworkDefenseWeb.Web.Contracts.DescribeManifestPlanGroup do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  alias NetworkDefense.Optimization.ModelVariant

  @enum_values model_variant: ModelVariant.wire_values()

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :model_variant, :string
    field :strategy, :string
    field :budget, :integer
    field :selection_seeds, {:array, :integer}
  end

  @type t :: %__MODULE__{
          model_variant: String.t(),
          strategy: String.t(),
          budget: integer(),
          selection_seeds: [integer()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:model_variant, :strategy, :budget, :selection_seeds])
    |> validate_required([:model_variant, :strategy, :budget, :selection_seeds])
    |> validate_inclusion(:model_variant, @enum_values[:model_variant])
    |> validate_number(:budget, greater_than: 0)
  end
end
