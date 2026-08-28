defmodule NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportEdgeTraversal do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  embedded_schema do
    field :edge_id, :string
    field :traversal_probability, :float
  end

  @type t :: %__MODULE__{edge_id: String.t(), traversal_probability: float()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:edge_id, :traversal_probability])
    |> validate_required([:edge_id, :traversal_probability])
    |> validate_number(:traversal_probability,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1
    )
  end
end
