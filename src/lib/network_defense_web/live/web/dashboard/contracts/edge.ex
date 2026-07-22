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

  @data_contracts %{
    "Runs" => NetworkDefenseWeb.Web.Contracts.Data.RunsData,
    "NetworkReachability" => NetworkDefenseWeb.Web.Contracts.Data.NetworkReachabilityData,
    "HasVulnerability" => NetworkDefenseWeb.Web.Contracts.Data.HasVulnerabilityData,
    "Elixir.NetworkDefense.Relationships.Runs" => NetworkDefenseWeb.Web.Contracts.Data.RunsData,
    "Elixir.NetworkDefense.Relationships.NetworkReachability" =>
      NetworkDefenseWeb.Web.Contracts.Data.NetworkReachabilityData,
    "Elixir.NetworkDefense.Relationships.HasVulnerability" =>
      NetworkDefenseWeb.Web.Contracts.Data.HasVulnerabilityData
  }

  embedded_schema do
    field :id, :string
    field :from_id, :string
    field :to_id, :string
    field :type, :string
    field :data, :map
  end

  @type t :: %__MODULE__{
          id: String.t(),
          from_id: String.t(),
          to_id: String.t(),
          type: String.t(),
          data:
            NetworkDefenseWeb.Web.Contracts.Data.RunsData.t()
            | NetworkDefenseWeb.Web.Contracts.Data.NetworkReachabilityData.t()
            | NetworkDefenseWeb.Web.Contracts.Data.HasVulnerabilityData.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :from_id, :to_id, :type, :data])
    |> validate_required([:id, :from_id, :to_id, :type, :data])
    |> validate_data()
  end

  defp validate_data(changeset) do
    case Map.get(@data_contracts, get_field(changeset, :type)) do
      nil -> add_error(changeset, :type, "is invalid")
      module -> validate_data(changeset, module)
    end
  end

  defp validate_data(changeset, module) do
    case module.validate(get_field(changeset, :data) || %{}) do
      {:ok, data} -> put_change(changeset, :data, to_params(data))
      {:error, _changeset} -> add_error(changeset, :data, "is invalid")
    end
  end
end
