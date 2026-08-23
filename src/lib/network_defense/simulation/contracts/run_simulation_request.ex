defmodule NetworkDefense.Simulation.Contracts.RunSimulationRequest do
  @moduledoc false

  alias NetworkDefense.Simulation.Contracts.SimulationParams

  use NetworkDefense.Contracts, category: :simulation

  embedded_schema do
    field :graph_revision_id, :string
    field :correlation_id, :string
    embeds_one :simulation_params, SimulationParams, on_replace: :update
  end

  @type t :: %__MODULE__{
          graph_revision_id: String.t(),
          correlation_id: String.t(),
          simulation_params: SimulationParams.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:graph_revision_id, :correlation_id])
    |> cast_embed(:simulation_params, required: true)
    |> validate_required([:graph_revision_id, :correlation_id])
    |> validate_length(:graph_revision_id, min: 1)
    |> Contracts.validate_uuid(:graph_revision_id)
    |> validate_length(:correlation_id, min: 1, max: 128)
  end
end
