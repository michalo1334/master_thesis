defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.SetGraphRevisionFavoriteReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  @enum_values status: [:ok, :not_found, :invalid_graph, :unmapped_error]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string
    field :favorite, :boolean
  end

  @type t :: %__MODULE__{
          status: String.t(),
          favorite: boolean()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status, :favorite])
    |> validate_required([:status, :favorite])
    |> validate_inclusion(:status, ["ok", "not_found", "invalid_graph", "unmapped_error"])
  end
end
