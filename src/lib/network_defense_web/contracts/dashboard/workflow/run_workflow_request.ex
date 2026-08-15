defmodule NetworkDefenseWeb.Web.Contracts.RunWorkflowRequest do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :workflow

  alias NetworkDefense.Optimization.Contracts.OptimizationParams
  alias NetworkDefense.Simulation.Contracts.SimulationParams

  @enum_values template: [:combined_analysis]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :template, :string
    field :graph_revision_id, :string
    field :correlation_id, :string
    embeds_one :simulation_params, SimulationParams, on_replace: :update
    embeds_one :optimization_params, OptimizationParams, on_replace: :update
  end

  @type t :: %__MODULE__{
          template: String.t(),
          graph_revision_id: String.t(),
          correlation_id: String.t(),
          simulation_params: SimulationParams.t(),
          optimization_params: OptimizationParams.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:template, :graph_revision_id, :correlation_id])
    |> cast_embed(:simulation_params, required: true)
    |> cast_embed(:optimization_params, required: true)
    |> validate_required([:template, :graph_revision_id, :correlation_id])
    |> validate_inclusion(:template, ["combined_analysis"])
    |> validate_length(:correlation_id, min: 1)
    |> NetworkDefense.Contracts.validate_uuid(:graph_revision_id)
  end
end
