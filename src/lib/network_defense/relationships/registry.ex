defmodule NetworkDefense.Relationships.Registry do
  alias NetworkDefense.Relationships.AuthenticatesTo
  alias NetworkDefense.Relationships.Contains
  alias NetworkDefense.Relationships.HasVulnerability
  alias NetworkDefense.Relationships.NetworkReachability
  alias NetworkDefense.Relationships.Runs
  alias NetworkDefense.Relationships.SegmentReachability
  alias NetworkDefense.Relationships.StoresCredential
  alias NetworkDefense.Relationships.Supports
  alias NetworkDefense.Registry

  @moduledoc """
  A registry containing all relationship currently available to be supplied to the simulator.

  Provides central place to manage all current and future relationships created in the source code

  `@types` includes the operational `NetworkReachability` marker used only by transient in-memory
  graphs. The canonical surface (`@canonical_types`) excludes it and exposes the persisted
  `SegmentReachability` policy edge.
  """

  @types [
    Runs,
    NetworkReachability,
    SegmentReachability,
    HasVulnerability,
    StoresCredential,
    AuthenticatesTo,
    Contains,
    Supports
  ]

  @canonical_types [
    Runs,
    SegmentReachability,
    HasVulnerability,
    StoresCredential,
    AuthenticatesTo,
    Contains,
    Supports
  ]

  def module_for(type), do: Registry.module_for(@types, type)
  def module_for_contract(type), do: Registry.module_for_short(@canonical_types, type)
  def type_for(module), do: Registry.type_for(@types, module)
  def contract_type_for(module), do: Registry.contract_type_for(@types, module)
  def contract_types, do: Registry.contract_types(@canonical_types)

  def canonical_types, do: @canonical_types
  def module_for_canonical(type), do: Registry.module_for(@canonical_types, type)

  def contract_type_for_canonical(module),
    do: Registry.contract_type_for(@canonical_types, module)

  def canonical_contract_types, do: Registry.contract_types(@canonical_types)
end
