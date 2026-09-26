defmodule NetworkDefense.Registry do
  @moduledoc false

  def get_all(types), do: MapSet.new(types)

  def module_for(types, type) when is_binary(type),
    do: Enum.find(types, &(Atom.to_string(&1) == type))

  def module_for(_types, _type), do: nil

  def module_for_short(types, type) when is_binary(type),
    do: Enum.find(types, &(contract_type_for(types, &1) == type))

  def module_for_short(_types, _type), do: nil

  def type_for(types, module), do: if(module in types, do: Atom.to_string(module))

  def contract_type_for(types, module) do
    if module in types, do: module |> Module.split() |> List.last()
  end

  def contract_type_for_short(types, type) when is_atom(type) do
    type
    |> Atom.to_string()
    |> Macro.camelize()
    |> then(&module_for_short(types, &1))
    |> then(&contract_type_for(types, &1))
  end

  def contract_type_for_short(_types, _type), do: nil

  def contract_types(types), do: Enum.map(types, &contract_type_for(types, &1))
end
