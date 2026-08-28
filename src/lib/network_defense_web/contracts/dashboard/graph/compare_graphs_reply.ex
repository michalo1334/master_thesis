defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.CompareGraphsReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  @enum_values status: [:ok, :not_found, :invalid_graph, :unmapped_error]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string

    embeds_one :result, NetworkDefenseWeb.Contracts.Dashboard.Graph.GraphDiffResult,
      on_replace: :update
  end

  @type t :: %__MODULE__{
          status: String.t(),
          result: NetworkDefenseWeb.Contracts.Dashboard.Graph.GraphDiffResult.t() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status])
    |> cast_embed(:result)
    |> validate_required([:status])
    |> validate_inclusion(:status, ["ok", "not_found", "invalid_graph", "unmapped_error"])
  end
end
