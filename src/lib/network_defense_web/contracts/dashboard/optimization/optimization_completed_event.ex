defmodule NetworkDefenseWeb.Web.Contracts.OptimizationCompletedEvent do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :optimization

  embedded_schema do
    field :correlation_id, :string
    field :graph_id, :string
    field :optimized_graph_id, :string
  end

  @type t :: %__MODULE__{
          correlation_id: String.t(),
          graph_id: String.t(),
          optimized_graph_id: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:correlation_id, :graph_id, :optimized_graph_id])
    |> validate_required([:correlation_id, :graph_id, :optimized_graph_id])
  end
end
