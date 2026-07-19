defmodule NetworkDefenseWeb.Web.Contracts.OpenGraphPayload do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  @type t :: %__MODULE__{
          graph_id: String.t()
        }
  defstruct [:graph_id]
end
