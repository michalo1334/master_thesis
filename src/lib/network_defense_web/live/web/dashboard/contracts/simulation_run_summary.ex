defmodule NetworkDefenseWeb.Web.Contracts.SimulationRunSummary do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  @type t :: %__MODULE__{
          id: String.t(),
          graph_id: String.t(),
          graph_title: String.t(),
          seed: integer(),
          simulation_count: integer(),
          iteration_count: integer(),
          runtime_ms: integer(),
          started_at: String.t()
        }
  defstruct [
    :id,
    :graph_id,
    :graph_title,
    :seed,
    :simulation_count,
    :iteration_count,
    :runtime_ms,
    :started_at
  ]
end
