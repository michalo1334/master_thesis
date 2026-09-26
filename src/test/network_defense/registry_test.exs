defmodule NetworkDefense.RegistryTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Nodes.Registry, as: NodeRegistry
  alias NetworkDefense.Relationships.Registry, as: RelationshipRegistry
  alias NetworkDefense.Registry

  alias NetworkDefense.Nodes.Host

  test "converts short atoms to contract tags through a registry" do
    assert Registry.contract_type_for_short([Host], :host) == "Host"
    assert NodeRegistry.contract_type_for_short(:mission_capability) == "MissionCapability"

    assert RelationshipRegistry.contract_type_for_canonical_short(:has_vulnerability) ==
             "HasVulnerability"
  end

  test "returns nil for unknown and non-canonical short atoms" do
    assert Registry.contract_type_for_short([Host], :unknown) == nil
    assert Registry.contract_type_for_short([Host], "host") == nil
    assert NodeRegistry.contract_type_for_short(:unknown) == nil
    assert RelationshipRegistry.contract_type_for_canonical_short(:network_reachability) == nil
  end
end
