defmodule NetworkDefense.Nodes.Registry do
  @moduledoc """
  A registry containing all node types currently available to be supplied to the simulator.

  Provides central place to manage all current and future node types created in the source code
  """
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Nodes.Service
  alias NetworkDefense.Nodes.Vulnerability

  @types [Host, Service, Vulnerability]

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
