defmodule NetworkDefenseWeb.Web.Contracts.FetchSimulationRunsPayload do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  @type t :: %__MODULE__{
          graph_ids: [String.t()]
        }
  defstruct [:graph_ids]
end
