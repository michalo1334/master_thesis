defmodule NetworkDefense.Relationships.Registry do
  alias NetworkDefense.Relationships.AuthenticatesTo
  alias NetworkDefense.Relationships.HasVulnerability
  alias NetworkDefense.Relationships.NetworkReachability
  alias NetworkDefense.Relationships.Runs
  alias NetworkDefense.Relationships.StoresCredential

  @moduledoc """
  A registry containing all relationship currently available to be supplied to the simulator.

  Provides central place to manage all current and future relationships created in the source code
  """

  @types [Runs, NetworkReachability, HasVulnerability, StoresCredential, AuthenticatesTo]

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
