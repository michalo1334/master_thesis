defmodule NetworkDefenseWeb.Web.Contracts.Data.HostData do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  @type t :: %__MODULE__{
          name: String.t()
        }
  defstruct [:name]
end
