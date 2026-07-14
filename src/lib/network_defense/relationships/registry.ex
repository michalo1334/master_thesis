defmodule NetworkDefense.Relationships.Registry do
  alias NetworkDefense.Relationships.HasNetworkLink
  alias NetworkDefense.Relationships.HasVulnerability
  alias NetworkDefense.Relationships.GrantsCapability
  alias NetworkDefense.Relationships.Runs
  alias NetworkDefense.Relationships.ListensOn

  @moduledoc """
  A registry containing all relationship currently available to be supplied to the simulator.

  Provides central place to manage all current and future relationships created in the source code
  """

  @types [ListensOn, Runs, GrantsCapability, HasVulnerability, HasNetworkLink]

  def get_all() do
    MapSet.new(@types)
  end

  def module_for(type) when is_binary(type) do
    Enum.find(@types, &(Atom.to_string(&1) == type))
  end

  def module_for(_type), do: nil

  def type_for(module) when module in @types, do: Atom.to_string(module)
  def type_for(_module), do: nil
end
