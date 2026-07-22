defmodule NetworkDefenseWeb.Web.Contracts.RunSimulationReply do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  @enum_values status: [:accepted, :rejected]

  def contract_meta, do: %{enum_values: @enum_values}

  @type t :: %__MODULE__{
          status: String.t(),
          graph_id: String.t(),
          correlation_id: String.t(),
          reason: String.t() | nil
        }
  defstruct [:status, :graph_id, :correlation_id, :reason]
end
