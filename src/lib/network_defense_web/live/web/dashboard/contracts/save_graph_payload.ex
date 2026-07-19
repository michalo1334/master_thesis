defmodule NetworkDefenseWeb.Web.Contracts.SaveGraphPayload do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  @type t :: %__MODULE__{
          graph: NetworkDefenseWeb.Web.Contracts.GraphContract.t()
        }
  defstruct [:graph]
end
