defmodule NetworkDefense.Graph.Contracts.Node do
  @moduledoc false

  use NetworkDefense.Contracts, category: :graph

  alias NetworkDefense.Contracts
  alias NetworkDefense.Graph.Domain.Adapter

  alias NetworkDefense.Graph.Contracts.Data.{
    CredentialData,
    HostData,
    ServiceData,
    VulnerabilityData
  }

  alias NetworkDefense.Graph.Contracts.NodeViewData

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

  @variants_by_domain Map.new(@variants, fn {tag, {data_contract, domain_type}} ->
                        {domain_type, {tag, data_contract}}
                      end)

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
    |> validate_data()
  end

  def to_attrs(%__MODULE__{} = node) do
    with {:ok, {_data_contract, domain_type}} <- variant_for(node.type) do
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
    end
  end

  def from_domain(node) do
    with {:ok, {tag, data_contract}} <- variant_for_domain(node.type),
         {:ok, data} <- data_contract.validate(Adapter.data_params(node.data)),
         {:ok, view_data} <- NodeViewData.validate(Contracts.to_params(node.view_data)) do
      validate(%{
        id: node.id,
        type: Atom.to_string(tag),
        data: Contracts.to_wire(data),
        view_data: Contracts.to_wire(view_data)
      })
    end
  end

  defp validate_data(changeset) do
    case variant_for(get_field(changeset, :type)) do
      {:ok, {data_contract, _domain_type}} -> validate_data(changeset, data_contract)
      :error -> add_error(changeset, :type, "is invalid")
    end
  end

  defp validate_data(changeset, module) do
    case module.validate(get_field(changeset, :data) || %{}) do
      {:ok, data} -> put_change(changeset, :data, data)
      {:error, _changeset} -> add_error(changeset, :data, "is invalid")
    end
  end

  defp variant_for(type) when is_binary(type) do
    type
    |> String.to_existing_atom()
    |> then(&Keyword.fetch(@variants, &1))
  rescue
    ArgumentError -> :error
  end

  defp variant_for(_type), do: :error

  defp variant_for_domain(type) when is_atom(type), do: Map.fetch(@variants_by_domain, type)

  defp variant_for_domain(_type), do: :error
end
