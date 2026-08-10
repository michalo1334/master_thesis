defmodule NetworkDefense.Graph.Contracts.Edge do
  @moduledoc false

  use NetworkDefense.Contracts, category: :graph

  alias NetworkDefense.Contracts
  alias NetworkDefense.Graph.Data
  alias NetworkDefense.Graph.Contracts.Variant

  alias NetworkDefense.Graph.Contracts.Data.{
    AuthenticatesToData,
    ContainsData,
    HasVulnerabilityData,
    RunsData,
    SegmentReachabilityData,
    StoresCredentialData,
    SupportsData
  }

  @discriminant [
    field: :type,
    data_field: :data,
    variants: [
      Runs: RunsData,
      SegmentReachability: SegmentReachabilityData,
      HasVulnerability: HasVulnerabilityData,
      StoresCredential: StoresCredentialData,
      AuthenticatesTo: AuthenticatesToData,
      Contains: ContainsData,
      Supports: SupportsData
    ]
  ]

  def contract_meta, do: %{discriminant: @discriminant}

  @variants [
    Runs: {RunsData, NetworkDefense.Relationships.Runs},
    SegmentReachability:
      {SegmentReachabilityData, NetworkDefense.Relationships.SegmentReachability},
    HasVulnerability: {HasVulnerabilityData, NetworkDefense.Relationships.HasVulnerability},
    StoresCredential: {StoresCredentialData, NetworkDefense.Relationships.StoresCredential},
    AuthenticatesTo: {AuthenticatesToData, NetworkDefense.Relationships.AuthenticatesTo},
    Contains: {ContainsData, NetworkDefense.Relationships.Contains},
    Supports: {SupportsData, NetworkDefense.Relationships.Supports}
  ]

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
            | SegmentReachabilityData.t()
            | HasVulnerabilityData.t()
            | StoresCredentialData.t()
            | AuthenticatesToData.t()
            | ContainsData.t()
            | SupportsData.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :from_id, :to_id, :type, :data])
    |> validate_required([:id, :from_id, :to_id, :type, :data])
    |> Contracts.validate_uuid(:id)
    |> Contracts.validate_uuid(:from_id)
    |> Contracts.validate_uuid(:to_id)
    |> validate_data()
  end

  def to_attrs(%__MODULE__{} = edge) do
    case Variant.for_type(edge.type, @variants) do
      {:ok, {_data_contract, domain_type}} ->
        {:ok,
         %{
           "id" => edge.id,
           "from_id" => edge.from_id,
           "to_id" => edge.to_id,
           "type" => Atom.to_string(domain_type),
           "data" => Contracts.to_params(edge.data)
         }}

      :error ->
        :error
    end
  end

  def from_domain(edge) do
    with {:ok, {tag, data_contract}} <- Variant.for_domain(edge.type, @variants),
         {:ok, data} <- data_contract.validate(Data.to_params(edge.data)) do
      validate(%{
        id: edge.id,
        from_id: edge.from_id,
        to_id: edge.to_id,
        type: Atom.to_string(tag),
        data: Contracts.to_wire(data)
      })
    end
  end

  defp validate_data(changeset), do: Variant.validate_data(changeset, @variants)
end
