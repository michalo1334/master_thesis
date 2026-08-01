defmodule NetworkDefenseWeb.Web.Contracts.CompareGraphsPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    embeds_one :base_graph, NetworkDefense.Graph.Contracts.GraphContract, on_replace: :update
    field :comparison_graph_id, :string
  end

  @type t :: %__MODULE__{
          base_graph: NetworkDefense.Graph.Contracts.GraphContract.t(),
          comparison_graph_id: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:comparison_graph_id])
    |> cast_embed(:base_graph, required: true)
    |> validate_required([:comparison_graph_id])
    |> validate_length(:comparison_graph_id, min: 1)
    |> Contracts.validate_uuid(:comparison_graph_id)
  end
end
