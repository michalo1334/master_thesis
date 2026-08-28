defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.GraphDiffResult do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  alias NetworkDefense.Graph.Contracts.GraphContract
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.GraphDiffCounts
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.GraphDiffStatusEntry

  embedded_schema do
    embeds_one :graph, GraphContract, on_replace: :update

    embeds_many :node_status, GraphDiffStatusEntry, on_replace: :delete

    embeds_many :edge_status, GraphDiffStatusEntry, on_replace: :delete

    embeds_one :node_counts, GraphDiffCounts, on_replace: :update

    embeds_one :edge_counts, GraphDiffCounts, on_replace: :update
  end

  @type t :: %__MODULE__{
          graph: GraphContract.t(),
          node_status: [GraphDiffStatusEntry.t()],
          edge_status: [GraphDiffStatusEntry.t()],
          node_counts: GraphDiffCounts.t(),
          edge_counts: GraphDiffCounts.t()
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
