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

  @data_contracts %{
    "Host" => NetworkDefenseWeb.Web.Contracts.Data.HostData,
    "Service" => NetworkDefenseWeb.Web.Contracts.Data.ServiceData,
    "Vulnerability" => NetworkDefenseWeb.Web.Contracts.Data.VulnerabilityData,
    "Elixir.NetworkDefense.Nodes.Host" => NetworkDefenseWeb.Web.Contracts.Data.HostData,
    "Elixir.NetworkDefense.Nodes.Service" => NetworkDefenseWeb.Web.Contracts.Data.ServiceData,
    "Elixir.NetworkDefense.Nodes.Vulnerability" =>
      NetworkDefenseWeb.Web.Contracts.Data.VulnerabilityData
  }

  embedded_schema do
    field :id, :string
    field :type, :string
    field :data, :map
    embeds_one :view_data, NetworkDefenseWeb.Web.Contracts.NodeViewData, on_replace: :update
  end

  @type t :: %__MODULE__{
          id: String.t(),
          type: String.t(),
          data:
            NetworkDefenseWeb.Web.Contracts.Data.HostData.t()
            | NetworkDefenseWeb.Web.Contracts.Data.ServiceData.t()
            | NetworkDefenseWeb.Web.Contracts.Data.VulnerabilityData.t(),
          view_data: NetworkDefenseWeb.Web.Contracts.NodeViewData.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :type, :data])
    |> cast_embed(:view_data, required: true)
    |> validate_required([:id, :type, :data])
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
