defmodule NetworkDefense.Rules.RegistryTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Rules.{
    AcquireCredentialRule,
    LocalVulnerabilityExploitation,
    Registry,
    RemoteServiceExploitation,
    ReuseCredentialRule
  }

  test "RRULE-01: ordered rule identifiers resolve to rule structs in the declared order" do
    assert {:ok,
            [
              %RemoteServiceExploitation{},
              %LocalVulnerabilityExploitation{},
              %AcquireCredentialRule{},
              %ReuseCredentialRule{}
            ]} = Registry.resolve(Registry.values())
  end

  test "RRULE-01: a partial order resolves to the same order" do
    assert {:ok, [%ReuseCredentialRule{}, %RemoteServiceExploitation{}]} =
             Registry.resolve([:reuse_credential_rule, :remote_service_exploitation])
  end

  test "RRULE-01: the default rule structs follow the declared order" do
    assert Registry.default_rules() == [
             %RemoteServiceExploitation{},
             %LocalVulnerabilityExploitation{},
             %AcquireCredentialRule{},
             %ReuseCredentialRule{}
           ]
  end

  test "the registry exposes stable snake-case identifiers, never module names" do
    assert Registry.values() == [
             :remote_service_exploitation,
             :local_vulnerability_exploitation,
             :acquire_credential_rule,
             :reuse_credential_rule
           ]

    assert Registry.module_for(:reuse_credential_rule) == ReuseCredentialRule
    assert Registry.module_for(:unknown_rule) == nil
  end

  test "an unknown or empty rule identifier list is rejected" do
    assert {:error, :unknown_rule} = Registry.resolve([:unknown_rule])
    assert {:error, :unknown_rule} = Registry.resolve([])
    assert {:error, :unknown_rule} = Registry.resolve(nil)
  end
end
