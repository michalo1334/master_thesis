defmodule NetworkDefenseWeb.Web.Contracts.OpenGraphReply do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  @enum_values status: [:ok, :stale, :not_found, :unmapped_error]

  def contract_meta, do: %{enum_values: @enum_values}

  @type t :: %__MODULE__{
          status: String.t(),
          graph: NetworkDefenseWeb.Web.Contracts.GraphContract.t() | nil
        }
  defstruct [:status, :graph]
end
