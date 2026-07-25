defmodule NetworkDefense.Graph.SemanticConnectivity do
  @moduledoc false

  alias NetworkDefense.Nodes.{Credential, Host, Service, Vulnerability}

  alias NetworkDefense.Relationships.{
    AuthenticatesTo,
    HasVulnerability,
    NetworkReachability,
    Runs,
    StoresCredential
  }

  @allowed_endpoints %{
    Runs => [{Host, Service}],
    NetworkReachability => [{Host, Service}],
    HasVulnerability => [{Host, Vulnerability}, {Service, Vulnerability}],
    StoresCredential => [{Host, Credential}],
    AuthenticatesTo => [{Credential, Service}]
  }

  def valid?(relationship_type, from_type, to_type)
      when is_atom(relationship_type) and is_atom(from_type) and is_atom(to_type),
      do: Map.get(@allowed_endpoints, relationship_type, []) |> Enum.member?({from_type, to_type})

  def valid?(_relationship_type, _from_type, _to_type), do: false
end
