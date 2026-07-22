defmodule NetworkDefenseWeb.Web.Contracts.RunSimulationRequest do
  @moduledoc false
  alias NetworkDefenseWeb.Web.Contracts.SimulationParams

  use NetworkDefenseWeb.Web.Contracts

  embedded_schema do
    field :graph_id, :string
    field :correlation_id, :string
    embeds_one :simulation_params, SimulationParams, on_replace: :update
  end

  @type t :: %__MODULE__{
          graph_id: String.t(),
          correlation_id: String.t(),
          simulation_params: SimulationParams.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:graph_id, :correlation_id])
    |> cast_embed(:simulation_params, required: true)
    |> validate_required([:graph_id, :correlation_id])
    |> validate_length(:graph_id, min: 1)
    |> validate_length(:correlation_id, min: 1)
  end
end
