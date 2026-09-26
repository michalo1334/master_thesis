defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjection.Attachment do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjection.Anchor

  @node_types ~w(Vulnerability Credential MissionCapability)

  @enum_values node_type: @node_types

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :id, :string
    field :node_type, :string
    embeds_many :anchors, Anchor, on_replace: :delete
  end

  @type t :: %__MODULE__{
          id: String.t(),
          node_type: String.t(),
          anchors: [Anchor.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :node_type])
    |> cast_embed(:anchors)
    |> validate_required([:id, :node_type])
    |> Contracts.validate_uuid(:id)
    |> validate_inclusion(:node_type, @node_types)
  end
end
