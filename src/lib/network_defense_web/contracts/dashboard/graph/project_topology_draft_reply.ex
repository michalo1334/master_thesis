defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.ProjectTopologyDraftReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.GraphValidationError
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjection

  @enum_values status: [:ok, :invalid_graph, :unmapped_error]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string
    field :document_id, :string
    field :semantic_version, :integer
    embeds_one :topology_projection, TopologyProjection, on_replace: :update
    embeds_many :errors, GraphValidationError, on_replace: :delete
  end

  @type t :: %__MODULE__{
          status: String.t(),
          document_id: String.t() | nil,
          semantic_version: non_neg_integer() | nil,
          topology_projection: TopologyProjection.t() | nil,
          errors: [GraphValidationError.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status, :document_id, :semantic_version])
    |> cast_embed(:topology_projection)
    |> cast_embed(:errors)
    |> validate_required([:status])
    |> validate_inclusion(:status, ["ok", "invalid_graph", "unmapped_error"])
    |> Contracts.validate_uuid(:document_id)
    |> validate_number(:semantic_version, greater_than_or_equal_to: 0)
  end
end
