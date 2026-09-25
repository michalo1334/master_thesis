defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.SaveGraphReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  alias NetworkDefense.Graph.Contracts.GraphContract
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.GraphValidationError
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjection

  @enum_values status: [:ok, :stale, :not_found, :invalid_graph, :unmapped_error]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string
    embeds_one :graph, GraphContract, on_replace: :update
    embeds_one :topology_projection, TopologyProjection, on_replace: :update
    embeds_many :errors, GraphValidationError, on_replace: :delete
  end

  @type t :: %__MODULE__{
          status: String.t(),
          graph: GraphContract.t() | nil,
          topology_projection: TopologyProjection.t() | nil,
          errors: [GraphValidationError.t()] | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status])
    |> cast_embed(:graph)
    |> cast_embed(:topology_projection)
    |> cast_embed(:errors)
    |> validate_required([:status])
    |> validate_inclusion(:status, ["ok", "stale", "not_found", "invalid_graph", "unmapped_error"])
  end
end
