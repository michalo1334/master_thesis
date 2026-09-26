defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjection.PolicyGroup do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    field :from_segment_id, :string
    field :to_segment_id, :string
    field :edge_ids, {:array, :string}, default: []
  end

  @type t :: %__MODULE__{
          from_segment_id: String.t(),
          to_segment_id: String.t(),
          edge_ids: [String.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:from_segment_id, :to_segment_id, :edge_ids])
    |> validate_required([:from_segment_id, :to_segment_id])
    |> Contracts.validate_uuid(:from_segment_id)
    |> Contracts.validate_uuid(:to_segment_id)
    |> validate_change(:edge_ids, fn :edge_ids, edge_ids ->
      if Enum.all?(edge_ids, &match?({:ok, _}, Ecto.UUID.cast(&1))) do
        []
      else
        [edge_ids: "contains an invalid UUID"]
      end
    end)
  end
end
