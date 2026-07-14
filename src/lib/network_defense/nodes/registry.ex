defmodule NetworkDefense.Nodes.Registry do
  @moduledoc """
  A registry containing all node types currently available to be supplied to the simulator.

  Provides central place to manage all current and future node types created in the source code
  """
  alias NetworkDefense.Nodes.Capability
  alias NetworkDefense.Nodes.Vulnerability
  alias NetworkDefense.Graph.Nodes.Host
  alias NetworkDefense.Nodes.Application
  alias NetworkDefense.Graph.Nodes.Port

  @types [Host, Port, Application, Vulnerability, Capability]

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
