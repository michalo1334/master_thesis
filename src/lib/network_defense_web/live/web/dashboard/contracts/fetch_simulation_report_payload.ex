defmodule NetworkDefenseWeb.Web.Contracts.FetchSimulationReportPayload do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  @type t :: %__MODULE__{
          multi_state_id: String.t(),
          graph_id: String.t()
        }
  defstruct [:multi_state_id, :graph_id]
end
