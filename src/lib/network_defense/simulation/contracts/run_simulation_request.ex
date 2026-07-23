defmodule NetworkDefense.Simulation.Contracts.RunSimulationRequest do
  @moduledoc false

  alias NetworkDefense.Simulation.Contracts.SimulationParams

  use NetworkDefense.Contracts, category: :dashboard

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
    |> validate_uuid(:graph_id)
    |> validate_length(:correlation_id, min: 1)
  end

  defp validate_uuid(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      case Ecto.UUID.cast(value) do
        {:ok, _uuid} -> []
        :error -> [{field, "is invalid"}]
      end
    end)
  end
end
