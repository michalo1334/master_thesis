defmodule NetworkDefense.Graph.SemanticConnectivity do
  @moduledoc false

  alias NetworkDefense.Nodes.{Credential, Host, NetworkSegment, Service, Vulnerability}
  alias NetworkDefense.Nodes.Registry, as: NodeRegistry

  alias NetworkDefense.Relationships.{
    AuthenticatesTo,
    Contains,
    HasVulnerability,
    NetworkReachability,
    Runs,
    SegmentReachability,
    StoresCredential
  }

  alias NetworkDefense.Relationships.Registry, as: RelationshipRegistry

  @allowed_endpoints %{
    Runs => [{Host, Service}],
    NetworkReachability => [{Host, Service}],
    SegmentReachability => [{NetworkSegment, NetworkSegment}],
    HasVulnerability => [{Host, Vulnerability}, {Service, Vulnerability}],
    StoresCredential => [{Host, Credential}],
    AuthenticatesTo => [{Credential, Service}],
    Contains => [{NetworkSegment, Host}]
  }

  @canonical_endpoints %{
    Runs => [{Host, Service}],
    SegmentReachability => [{NetworkSegment, NetworkSegment}],
    HasVulnerability => [{Host, Vulnerability}, {Service, Vulnerability}],
    StoresCredential => [{Host, Credential}],
    AuthenticatesTo => [{Credential, Service}],
    Contains => [{NetworkSegment, Host}]
  }

  def valid?(relationship_type, from_type, to_type)
      when is_atom(relationship_type) and is_atom(from_type) and is_atom(to_type),
      do: Map.get(@allowed_endpoints, relationship_type, []) |> Enum.member?({from_type, to_type})

  def valid?(_relationship_type, _from_type, _to_type), do: false

  def rules do
    for {relationship, endpoints} <- @canonical_endpoints,
        {from, to} <- endpoints do
      %{
        relationship_type: RelationshipRegistry.contract_type_for_canonical(relationship),
        from_type: NodeRegistry.contract_type_for(from),
        to_type: NodeRegistry.contract_type_for(to)
      }
    end
  end
end
