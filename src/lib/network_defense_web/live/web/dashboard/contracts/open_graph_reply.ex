defmodule NetworkDefenseWeb.Web.Contracts.OpenGraphReply do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  @enum_values status: [:ok, :stale, :not_found, :invalid_graph, :unmapped_error]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string
    embeds_one :graph, NetworkDefenseWeb.Web.Contracts.GraphContract, on_replace: :update
  end

  @type t :: %__MODULE__{
          status: String.t(),
          graph: NetworkDefenseWeb.Web.Contracts.GraphContract.t() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status])
    |> cast_embed(:graph)
    |> validate_required([:status])
    |> validate_inclusion(:status, ["ok", "stale", "not_found", "invalid_graph", "unmapped_error"])
  end
end
