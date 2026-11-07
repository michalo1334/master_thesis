defmodule Mix.Tasks.Gen.Contracts.RuntimeValues do
  @moduledoc false

  alias NetworkDefense.Contracts

  def render(module) do
    module.contract_meta()
    |> Map.get(:runtime_values, [])
    |> Enum.map_join("", fn {name, value} ->
      prefix = "export const #{name} = "

      "\n" <>
        prefix <>
        literal(Contracts.to_wire(value), 0, String.length(prefix) + 10) <> " as const;\n"
    end)
  end

  defp literal(value, _indent, _prefix) when is_map(value) and map_size(value) == 0, do: "{}"

  defp literal(value, indent, _prefix) when is_map(value) do
    properties =
      value
      |> Enum.sort()
      |> Enum.map_join(",\n", fn {key, item} ->
        key = property(to_string(key))
        spaces(indent + 2) <> key <> ": " <> literal(item, indent + 2, String.length(key) + 2)
      end)

    "{\n" <> properties <> ",\n" <> spaces(indent) <> "}"
  end

  defp literal(value, indent, prefix) when is_list(value) do
    inline = "[" <> Enum.map_join(value, ", ", &Jason.encode!/1) <> "]"

    if Enum.all?(value, &(not is_map(&1) and not is_list(&1))) and
         String.length(inline) + indent + prefix <= 80 do
      inline
    else
      "[\n" <>
        Enum.map_join(value, ",\n", &(spaces(indent + 2) <> literal(&1, indent + 2, 0))) <>
        ",\n" <> spaces(indent) <> "]"
    end
  end

  defp literal(value, _indent, _prefix), do: Jason.encode!(value)
  defp spaces(count), do: String.duplicate(" ", count)

  defp property(key),
    do: if(Regex.match?(~r/^[A-Za-z_$][A-Za-z0-9_$]*$/, key), do: key, else: Jason.encode!(key))
end
