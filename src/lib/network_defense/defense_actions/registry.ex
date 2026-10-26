defmodule NetworkDefense.DefenseActions.Registry do
  @moduledoc """
  A registry containing all defense action types currently available to be supplied to the optimizer.

  Provides central place to manage all current and future defense actions created in the source code
  """
  alias NetworkDefense.DefenseActions.BlockSegmentReachability
  alias NetworkDefense.DefenseActions.PatchVulnerability
  alias NetworkDefense.DefenseActions.RevokeCredential
  alias NetworkDefense.Registry

  # The declared identifier of each action type. The identifier is the stable
  # contract value: JSON, YAML, and TypeScript carry it as a snake-case string,
  # and the in-memory form is the atom.
  @actions [
    block_segment_reachability: BlockSegmentReachability,
    patch_vulnerability: PatchVulnerability,
    revoke_credential: RevokeCredential
  ]

  @types Keyword.values(@actions)
  @values Keyword.keys(@actions)

  @type action_type ::
          :block_segment_reachability
          | :patch_vulnerability
          | :revoke_credential

  @spec get_all() :: MapSet.t(module())
  def get_all, do: Registry.get_all(@types)

  @spec values() :: [action_type()]
  def values, do: @values

  @spec module_for_value(action_type()) :: module() | nil
  def module_for_value(value), do: Keyword.get(@actions, value)

  @spec module_for(String.t()) :: module() | nil
  def module_for(type), do: Registry.module_for(@types, type)

  @spec module_for_short(String.t()) :: module() | nil
  def module_for_short(type), do: Registry.module_for_short(@types, type)

  @spec type_for(module()) :: String.t() | nil
  def type_for(module), do: Registry.type_for(@types, module)

  @spec short_type_for(module()) :: String.t() | nil
  def short_type_for(module), do: Registry.contract_type_for(@types, module)
end
