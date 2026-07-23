defmodule NetworkDefenseWeb.Web.Contracts.FetchSimulationRunsReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  embedded_schema do
    embeds_many :runs, NetworkDefenseWeb.Web.Contracts.SimulationRunSummary, on_replace: :delete
  end

  @type t :: %__MODULE__{
          runs: [NetworkDefenseWeb.Web.Contracts.SimulationRunSummary.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:runs)
  end
end
