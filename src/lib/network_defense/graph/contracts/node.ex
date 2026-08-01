defmodule NetworkDefense.Graph.Contracts.Node do
  @moduledoc false

  use NetworkDefense.Contracts, category: :graph

  alias NetworkDefense.Contracts
  alias NetworkDefense.Graph.Data

  alias NetworkDefense.Graph.Contracts.Data.{
    CredentialData,
    HostData,
    ServiceData,
    VulnerabilityData
  }

  alias NetworkDefense.Graph.Contracts.NodeViewData
  alias NetworkDefense.Graph.Contracts.Variant

  @discriminant [
    field: :type,
    data_field: :data,
    variants: [
      Host: HostData,
      Service: ServiceData,
      Vulnerability: VulnerabilityData,
      Credential: CredentialData
    ]
  ]

  def contract_meta, do: %{discriminant: @discriminant}

  @variants [
    Host: {HostData, NetworkDefense.Nodes.Host},
    Service: {ServiceData, NetworkDefense.Nodes.Service},
    Vulnerability: {VulnerabilityData, NetworkDefense.Nodes.Vulnerability},
    Credential: {CredentialData, NetworkDefense.Nodes.Credential}
  ]

  embedded_schema do
    field :id, :string
    field :type, :string
    field :data, :map
    embeds_one :view_data, NodeViewData, on_replace: :update
  end

  @type t :: %__MODULE__{
          id: String.t(),
          type: String.t(),
          data:
            HostData.t()
            | ServiceData.t()
            | VulnerabilityData.t()
            | CredentialData.t(),
          view_data: NodeViewData.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :type, :data])
    |> cast_embed(:view_data, required: true)
    |> validate_required([:id, :type, :data])
    |> Contracts.validate_uuid(:id)
    |> validate_data()
  end

  def to_attrs(%__MODULE__{} = node) do
    case Variant.for_type(node.type, @variants) do
      {:ok, {_data_contract, domain_type}} ->
        {:ok,
         %{
           "id" => node.id,
           "type" => Atom.to_string(domain_type),
           "data" => Contracts.to_params(node.data),
           "view_data" =>
             node.view_data
             |> Contracts.to_params()
             |> Map.reject(fn {_key, value} -> is_nil(value) end)
         }}

      :error ->
        :error
    end
  end

  def from_domain(node) do
    with {:ok, {tag, data_contract}} <- Variant.for_domain(node.type, @variants),
         {:ok, data} <- data_contract.validate(Data.to_params(node.data)),
         {:ok, view_data} <- NodeViewData.validate(Contracts.to_params(node.view_data)) do
      validate(%{
        id: node.id,
        type: Atom.to_string(tag),
        data: Contracts.to_wire(data),
        view_data: Contracts.to_wire(view_data)
      })
    end
  end

  defp validate_data(changeset), do: Variant.validate_data(changeset, @variants)
end
