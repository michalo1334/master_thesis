defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.CreateNodeDraftPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  @node_types NetworkDefense.Nodes.Registry.contract_types()
  @enum_values node_type: @node_types

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :node_type, :string
    field :x_pos, :float
    field :y_pos, :float
  end

  @type t :: %__MODULE__{
          node_type: String.t(),
          x_pos: float(),
          y_pos: float()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:node_type, :x_pos, :y_pos])
    |> validate_required([:node_type, :x_pos, :y_pos])
    |> validate_inclusion(:node_type, @node_types)
  end
end
