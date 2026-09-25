defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjectionAnchor do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  @relationship_types ~w(HasVulnerability StoresCredential AuthenticatesTo Supports)

  @enum_values relationship_type: @relationship_types

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :node_id, :string
    field :edge_id, :string
    field :relationship_type, :string
  end

  @type t :: %__MODULE__{
          node_id: String.t(),
          edge_id: String.t(),
          relationship_type: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:node_id, :edge_id, :relationship_type])
    |> validate_required([:node_id, :edge_id, :relationship_type])
    |> Contracts.validate_uuid(:node_id)
    |> Contracts.validate_uuid(:edge_id)
    |> validate_inclusion(:relationship_type, @relationship_types)
  end
end
