defmodule NetworkDefense.Nodes.Registry do
  @moduledoc """
  A registry containing all node types currently available to be supplied to the simulator.

  Provides central place to manage all current and future node types created in the source code
  """
  alias NetworkDefense.Nodes.Credential
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Nodes.MissionCapability
  alias NetworkDefense.Nodes.NetworkSegment
  alias NetworkDefense.Nodes.Service
  alias NetworkDefense.Nodes.Vulnerability
  alias NetworkDefense.Registry

  @types [Host, Service, Vulnerability, Credential, NetworkSegment, MissionCapability]

  def module_for(type), do: Registry.module_for(@types, type)
  def module_for_contract(type), do: Registry.module_for_short(@types, type)
  def type_for(module), do: Registry.type_for(@types, module)
  def contract_type_for(module), do: Registry.contract_type_for(@types, module)
  def contract_types, do: Registry.contract_types(@types)
end
