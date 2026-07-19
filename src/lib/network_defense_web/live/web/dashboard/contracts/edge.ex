defmodule NetworkDefenseWeb.Web.Contracts.Edge do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  @discriminant [
    field: :type,
    data_field: :data,
    variants: [
      Runs: NetworkDefenseWeb.Web.Contracts.Data.RunsData,
      NetworkReachability: NetworkDefenseWeb.Web.Contracts.Data.NetworkReachabilityData,
      HasVulnerability: NetworkDefenseWeb.Web.Contracts.Data.HasVulnerabilityData
    ]
  ]

  def contract_meta, do: %{discriminant: @discriminant}

  @type t :: %__MODULE__{
          id: String.t(),
          from_id: String.t(),
          to_id: String.t(),
          type: atom(),
          data:
            NetworkDefenseWeb.Web.Contracts.Data.RunsData.t()
            | NetworkDefenseWeb.Web.Contracts.Data.NetworkReachabilityData.t()
            | NetworkDefenseWeb.Web.Contracts.Data.HasVulnerabilityData.t()
        }
  defstruct [:id, :from_id, :to_id, :type, :data]
end
