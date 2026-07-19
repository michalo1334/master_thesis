defmodule NetworkDefenseWeb.Web.Contracts.Node do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  @discriminant [
    field: :type,
    data_field: :data,
    variants: [
      Host: NetworkDefenseWeb.Web.Contracts.Data.HostData,
      Service: NetworkDefenseWeb.Web.Contracts.Data.ServiceData,
      Vulnerability: NetworkDefenseWeb.Web.Contracts.Data.VulnerabilityData
    ]
  ]

  def contract_meta, do: %{discriminant: @discriminant}

  @type t :: %__MODULE__{
          id: String.t(),
          type: atom(),
          data:
            NetworkDefenseWeb.Web.Contracts.Data.HostData.t()
            | NetworkDefenseWeb.Web.Contracts.Data.ServiceData.t()
            | NetworkDefenseWeb.Web.Contracts.Data.VulnerabilityData.t(),
          view_data: NetworkDefenseWeb.Web.Contracts.NodeViewData.t()
        }
  defstruct [:id, :type, :data, :view_data]
end
