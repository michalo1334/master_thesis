defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.ProjectTopologyDraftPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  alias NetworkDefense.Graph.Contracts.GraphContract

  embedded_schema do
    field :document_id, :string
    field :semantic_version, :integer
    embeds_one :graph, GraphContract, on_replace: :update
  end

  @type t :: %__MODULE__{
          document_id: String.t(),
          semantic_version: non_neg_integer(),
          graph: GraphContract.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:document_id, :semantic_version])
    |> cast_embed(:graph)
    |> validate_required([:document_id, :semantic_version, :graph])
    |> Contracts.validate_uuid(:document_id)
    |> validate_number(:semantic_version, greater_than_or_equal_to: 0)
  end
end
