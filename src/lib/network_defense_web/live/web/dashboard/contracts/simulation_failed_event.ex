defmodule NetworkDefenseWeb.Web.Contracts.SimulationFailedEvent do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  @type t :: %__MODULE__{
          correlation_id: String.t(),
          graph_id: String.t(),
          reason: String.t()
        }
  defstruct [:correlation_id, :graph_id, :reason]
end
