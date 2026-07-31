defmodule NetworkDefenseWeb.Web.Contracts.CreateConnectionDraftReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  @enum_values status: [:ok, :invalid]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string
    embeds_one :node, NetworkDefense.Graph.Contracts.Node, on_replace: :update
    embeds_one :edge, NetworkDefense.Graph.Contracts.Edge, on_replace: :update
  end

  @type t :: %__MODULE__{
          status: String.t(),
          node: NetworkDefense.Graph.Contracts.Node.t() | nil,
          edge: NetworkDefense.Graph.Contracts.Edge.t() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status])
    |> cast_embed(:node)
    |> cast_embed(:edge)
    |> validate_required([:status])
    |> validate_inclusion(:status, ["ok", "invalid"])
  end
end
