defmodule NetworkDefenseWeb.Web.Contracts.SimulationCompletedEvent do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  @type t :: %__MODULE__{
          correlation_id: String.t(),
          graph_id: String.t(),
          simulation_id: String.t()
        }
  defstruct [:correlation_id, :graph_id, :simulation_id]
end
