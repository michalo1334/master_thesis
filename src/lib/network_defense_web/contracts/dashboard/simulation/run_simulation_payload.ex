defmodule NetworkDefenseWeb.Web.Contracts.RunSimulationPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  alias NetworkDefense.Simulation.Contracts.RunSimulationRequest

  embedded_schema do
    embeds_one :request, RunSimulationRequest, on_replace: :update
  end

  @type t :: %__MODULE__{request: RunSimulationRequest.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:request, required: true)
  end
end
