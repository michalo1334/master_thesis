defmodule NetworkDefense.DefenseActions.Registry do
  @moduledoc """
  A registry containing all defense action types currently available to be supplied to the optimizer.

  Provides central place to manage all current and future defense actions created in the source code
  """
  alias NetworkDefense.DefenseActions.RevokeCredential
  alias NetworkDefense.DefenseActions.PatchVulnerability
  alias NetworkDefense.DefenseActions.BlockReachability

  @types [BlockReachability, PatchVulnerability, RevokeCredential]

  def get_all() do
    MapSet.new(@types)
  end

  def module_for(type) when is_binary(type) do
    Enum.find(@types, &(Atom.to_string(&1) == type))
  end

  def module_for(_type), do: nil

  def module_for_short(short) when is_binary(short) do
    Enum.find(@types, &(Module.split(&1) |> List.last() == short))
  end

  def module_for_short(_), do: nil

  def type_for(module) when module in @types, do: Atom.to_string(module)
  def type_for(_module), do: nil
end
