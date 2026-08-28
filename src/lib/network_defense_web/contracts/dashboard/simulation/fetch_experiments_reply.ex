defmodule NetworkDefenseWeb.Contracts.Dashboard.Simulation.FetchExperimentsReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.ExperimentSummary

  embedded_schema do
    embeds_many :experiments, ExperimentSummary, on_replace: :delete
  end

  @type t :: %__MODULE__{
          experiments: [ExperimentSummary.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:experiments)
  end
end
