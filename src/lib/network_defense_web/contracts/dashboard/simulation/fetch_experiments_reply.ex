defmodule NetworkDefenseWeb.Contracts.Dashboard.Simulation.FetchExperimentsReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  embedded_schema do
    embeds_many :experiments, NetworkDefenseWeb.Contracts.Dashboard.Simulation.ExperimentSummary,
      on_replace: :delete
  end

  @type t :: %__MODULE__{
          experiments: [NetworkDefenseWeb.Contracts.Dashboard.Simulation.ExperimentSummary.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:experiments)
  end
end
