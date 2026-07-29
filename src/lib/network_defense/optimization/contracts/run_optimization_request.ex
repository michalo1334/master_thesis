defmodule NetworkDefense.Optimization.Contracts.RunOptimizationRequest do
  @moduledoc false

  alias NetworkDefense.Optimization.Contracts.OptimizationParams

  use NetworkDefense.Contracts, category: :optimization

  embedded_schema do
    field :graph_id, :string
    field :correlation_id, :string
    embeds_one :optimization_params, OptimizationParams, on_replace: :update
  end

  @type t :: %__MODULE__{
          graph_id: String.t(),
          correlation_id: String.t(),
          optimization_params: OptimizationParams.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:graph_id, :correlation_id])
    |> cast_embed(:optimization_params, required: true)
    |> validate_required([:graph_id, :correlation_id])
    |> Contracts.validate_uuid(:graph_id)
    |> validate_length(:correlation_id, min: 1)
  end
end
