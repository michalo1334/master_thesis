defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.GraphValidationError do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  @enum_values entity_kind: [:graph, :node, :edge]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :entity_kind, :string
    field :entity_id, :string
    field :field_path, {:array, :string}
    field :message, :string
  end

  @type t :: %__MODULE__{
          entity_kind: String.t(),
          entity_id: String.t() | nil,
          field_path: [String.t()],
          message: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:entity_kind, :entity_id, :field_path, :message])
    |> validate_required([:entity_kind, :field_path, :message])
    |> validate_inclusion(:entity_kind, ["graph", "node", "edge"])
  end
end
