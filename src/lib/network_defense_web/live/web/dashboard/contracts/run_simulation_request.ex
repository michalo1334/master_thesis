defmodule NetworkDefenseWeb.Web.Contracts.RunSimulationRequest do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  @type t :: %__MODULE__{
          graph_id: String.t(),
          correlation_id: String.t()
        }
  defstruct [:graph_id, :correlation_id]
end
