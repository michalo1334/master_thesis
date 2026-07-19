defmodule NetworkDefenseWeb.Web.Contracts.Data.ServiceData do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  @enum_values protocol: [:tcp, :udp]

  def contract_meta, do: %{enum_values: @enum_values}

  @type t :: %__MODULE__{
          name: String.t(),
          protocol: atom(),
          port: integer(),
          version: String.t() | nil
        }
  defstruct [:name, :protocol, :port, :version]
end
