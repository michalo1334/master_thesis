defmodule NetworkDefense.Relationships.Registry do
  alias NetworkDefense.Relationships.AuthenticatesTo
  alias NetworkDefense.Relationships.HasVulnerability
  alias NetworkDefense.Relationships.NetworkReachability
  alias NetworkDefense.Relationships.Runs
  alias NetworkDefense.Relationships.StoresCredential
  alias NetworkDefense.Registry

  @moduledoc """
  A registry containing all relationship currently available to be supplied to the simulator.

  Provides central place to manage all current and future relationships created in the source code
  """

  @types [Runs, NetworkReachability, HasVulnerability, StoresCredential, AuthenticatesTo]

  def module_for(type), do: Registry.module_for(@types, type)
  def module_for_contract(type), do: Registry.module_for_short(@types, type)
  def type_for(module), do: Registry.type_for(@types, module)
  def contract_type_for(module), do: Registry.contract_type_for(@types, module)
  def contract_types, do: Registry.contract_types(@types)
end
