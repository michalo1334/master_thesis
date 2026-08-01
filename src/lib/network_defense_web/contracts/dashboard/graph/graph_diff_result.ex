defmodule NetworkDefenseWeb.Web.Contracts.GraphDiffResult do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    embeds_one :graph, NetworkDefense.Graph.Contracts.GraphContract, on_replace: :update

    embeds_many :node_status, NetworkDefenseWeb.Web.Contracts.GraphDiffStatusEntry,
      on_replace: :delete

    embeds_many :edge_status, NetworkDefenseWeb.Web.Contracts.GraphDiffStatusEntry,
      on_replace: :delete

    embeds_one :node_counts, NetworkDefenseWeb.Web.Contracts.GraphDiffCounts, on_replace: :update
    embeds_one :edge_counts, NetworkDefenseWeb.Web.Contracts.GraphDiffCounts, on_replace: :update
  end

  @type t :: %__MODULE__{
          graph: NetworkDefense.Graph.Contracts.GraphContract.t(),
          node_status: [NetworkDefenseWeb.Web.Contracts.GraphDiffStatusEntry.t()],
          edge_status: [NetworkDefenseWeb.Web.Contracts.GraphDiffStatusEntry.t()],
          node_counts: NetworkDefenseWeb.Web.Contracts.GraphDiffCounts.t(),
          edge_counts: NetworkDefenseWeb.Web.Contracts.GraphDiffCounts.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:graph, required: true)
    |> cast_embed(:node_status)
    |> cast_embed(:edge_status)
    |> cast_embed(:node_counts, required: true)
    |> cast_embed(:edge_counts, required: true)
  end
end
