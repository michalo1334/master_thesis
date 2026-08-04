defmodule NetworkDefense.DefenseActions.Registry do
  @moduledoc """
  A registry containing all defense action types currently available to be supplied to the optimizer.

  Provides central place to manage all current and future defense actions created in the source code
  """
  alias NetworkDefense.DefenseActions.RevokeCredential
  alias NetworkDefense.DefenseActions.PatchVulnerability
  alias NetworkDefense.DefenseActions.BlockSegmentReachability
  alias NetworkDefense.Registry

  @types [BlockSegmentReachability, PatchVulnerability, RevokeCredential]

  def get_all, do: Registry.get_all(@types)
  def module_for(type), do: Registry.module_for(@types, type)
  def module_for_short(type), do: Registry.module_for_short(@types, type)
  def type_for(module), do: Registry.type_for(@types, module)
  def short_type_for(module), do: Registry.contract_type_for(@types, module)
end
