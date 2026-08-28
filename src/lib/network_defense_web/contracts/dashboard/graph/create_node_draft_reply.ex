defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.CreateNodeDraftReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  @enum_values status: [:ok, :invalid]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string
    embeds_one :node, NetworkDefense.Graph.Contracts.Node, on_replace: :update
  end

  @type t :: %__MODULE__{
          status: String.t(),
          node: NetworkDefense.Graph.Contracts.Node.t() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status])
    |> cast_embed(:node)
    |> validate_required([:status])
    |> validate_inclusion(:status, ["ok", "invalid"])
  end
end
