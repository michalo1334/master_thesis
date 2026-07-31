defmodule NetworkDefenseWeb.Web.Contracts.GraphConnectivityRule do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  @node_types NetworkDefense.Nodes.Registry.contract_types()
  @relationship_types NetworkDefense.Relationships.Registry.contract_types()
  @enum_values from_type: @node_types,
               to_type: @node_types,
               relationship_type: @relationship_types

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :from_type, :string
    field :to_type, :string
    field :relationship_type, :string
  end

  @type t :: %__MODULE__{
          from_type: String.t(),
          to_type: String.t(),
          relationship_type: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:from_type, :to_type, :relationship_type])
    |> validate_required([:from_type, :to_type, :relationship_type])
    |> validate_inclusion(:from_type, @node_types)
    |> validate_inclusion(:to_type, @node_types)
    |> validate_inclusion(:relationship_type, @relationship_types)
  end
end
