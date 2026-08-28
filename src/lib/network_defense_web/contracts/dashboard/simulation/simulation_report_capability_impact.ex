defmodule NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportCapabilityImpact do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  embedded_schema do
    field :capability_id, :string
    field :down_probability, :float
  end

  @type t :: %__MODULE__{capability_id: String.t(), down_probability: float()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:capability_id, :down_probability])
    |> validate_required([:capability_id, :down_probability])
    |> validate_number(:down_probability, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
  end
end
