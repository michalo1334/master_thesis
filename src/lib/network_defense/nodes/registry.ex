defmodule NetworkDefense.Nodes.Registry do
  @moduledoc """
  A registry containing all node types currently available to be supplied to the simulator.

  Provides central place to manage all current and future node types created in the source code
  """
  alias NetworkDefense.Nodes.Credential
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Nodes.Service
  alias NetworkDefense.Nodes.Vulnerability

  @types [Host, Service, Vulnerability, Credential]

  def module_for(type) when is_binary(type) do
    Enum.find(@types, &(Atom.to_string(&1) == type))
  end

  def module_for(_type), do: nil

  def module_for_contract(type) when is_binary(type) do
    Enum.find(@types, &(contract_type_for(&1) == type))
  end

  def module_for_contract(_type), do: nil

  def type_for(module) when module in @types, do: Atom.to_string(module)
  def type_for(_module), do: nil

  def contract_type_for(module) when module in @types,
    do: module |> Module.split() |> List.last()

  def contract_type_for(_module), do: nil
  def contract_types, do: Enum.map(@types, &contract_type_for/1)
end
