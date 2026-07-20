defmodule NetworkDefenseWeb.Web.Contracts.FetchSimulationRunsReply do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  @type t :: %__MODULE__{
          runs: [NetworkDefenseWeb.Web.Contracts.SimulationRunSummary.t()]
        }
  defstruct [:runs]
end
