defmodule NetworkDefense.Graph.Contracts.Edge do
  @moduledoc false

  use NetworkDefense.Contracts, category: :dashboard

  alias NetworkDefense.Contracts

  alias NetworkDefense.Graph.Contracts.Data.{
    HasVulnerabilityData,
    NetworkReachabilityData,
    RunsData
  }

  @discriminant [
    field: :type,
    data_field: :data,
    variants: [
      Runs: RunsData,
      NetworkReachability: NetworkReachabilityData,
      HasVulnerability: HasVulnerabilityData
    ]
  ]

  def contract_meta, do: %{discriminant: @discriminant}

  @variants [
    Runs: {RunsData, NetworkDefense.Relationships.Runs},
    NetworkReachability:
      {NetworkReachabilityData, NetworkDefense.Relationships.NetworkReachability},
    HasVulnerability: {HasVulnerabilityData, NetworkDefense.Relationships.HasVulnerability}
  ]

  @variants_by_domain Map.new(@variants, fn {tag, {data_contract, domain_type}} ->
                        {domain_type, {tag, data_contract}}
                      end)

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
            RunsData.t()
            | NetworkReachabilityData.t()
            | HasVulnerabilityData.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :from_id, :to_id, :type, :data])
    |> validate_required([:id, :from_id, :to_id, :type, :data])
    |> validate_data()
  end

  def to_attrs(%__MODULE__{} = edge) do
    with {:ok, {_data_contract, domain_type}} <- variant_for(edge.type) do
      {:ok,
       %{
         "id" => edge.id,
         "from_id" => edge.from_id,
         "to_id" => edge.to_id,
         "type" => Atom.to_string(domain_type),
         "data" => Contracts.to_params(edge.data)
       }}
    end
  end

  def from_domain(edge) do
    with {:ok, {tag, data_contract}} <- variant_for_domain(edge.type),
         {:ok, data} <- data_contract.validate(edge.data || %{}) do
      validate(%{
        id: edge.id,
        from_id: edge.from_id,
        to_id: edge.to_id,
        type: Atom.to_string(tag),
        data: Contracts.to_wire(data)
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

  defp variant_for_domain(type) when is_binary(type) do
    type
    |> String.to_existing_atom()
    |> then(&Map.fetch(@variants_by_domain, &1))
  rescue
    ArgumentError -> :error
  end

  defp variant_for_domain(_type), do: :error
end
