defmodule NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportHostCompromise do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  embedded_schema do
    field :host_id, :string
    field :compromise_probability, :float
  end

  @type t :: %__MODULE__{host_id: String.t(), compromise_probability: float()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:host_id, :compromise_probability])
    |> validate_required([:host_id, :compromise_probability])
    |> validate_number(:compromise_probability,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1
    )
  end
end
