defmodule Mix.Tasks.Gen.Contracts.Renderer do
  @moduledoc false

  @basic_types %{
    atom: "string",
    binary: "string",
    boolean: "boolean",
    float: "number",
    integer: "number",
    non_neg_integer: "number",
    pos_integer: "number",
    term: "unknown"
  }

  def source_comment(module, detail \\ nil) do
    source = module.__info__(:compile)[:source] |> to_string()
    base = "// #{inspect(module)} (#{Path.relative_to(source, File.cwd!())})"
    if detail, do: base <> " — " <> detail, else: base
  end

  def interface(name, fields, overrides \\ %{}) do
    properties =
      Enum.map(fields, fn {field, type} ->
        property(field, type, Map.get(overrides, field))
      end)

    case properties do
      [] -> "export type #{name} = Record<never, never>;"
      _ -> "export interface #{name} {\n#{Enum.join(properties, "\n")}\n}"
    end
  end

  def property(field, type, override \\ nil) do
    optional = if override || !optional?(type), do: "", else: "?"
    ts_type = override || type(type)
    separator = if String.starts_with?(ts_type, "\n"), do: "", else: " "
    "  #{field}#{optional}:#{separator}#{ts_type};"
  end

  def type({:atom, _, nil}), do: "null"
  def type({:atom, _, value}) when is_atom(value), do: "\"#{value}\""

  def type({:remote_type, _, [{:atom, _, module}, {:atom, _, :t}, _]}) do
    module_name(module)
  end

  def type({:type, _, :list, [item]}), do: "#{type(item)}[]"

  def type({:type, _, :map, :any}), do: "Record<string, unknown>"

  def type({:type, _, :union, types}) do
    joined = Enum.map_join(types, " | ", &type/1)
    if String.length(joined) > 50, do: "\n    #{joined}", else: joined
  end

  def type({:type, _, type, []}), do: Map.get(@basic_types, type, "unknown")

  def type(_), do: "unknown"

  def union_modules({:type, _, :union, members}) do
    Enum.flat_map(members, &union_modules/1)
  end

  def union_modules({:remote_type, _, [{:atom, _, module}, {:atom, _, :t}, _]}), do: [module]
  def union_modules(_), do: []

  defp optional?({:type, _, :union, members}) do
    Enum.any?(members, &match?({:atom, _, nil}, &1))
  end

  defp optional?(_), do: false

  defp module_name(module) do
    case Module.split(module) do
      ["String"] -> "string"
      ["Integer"] -> "number"
      ["Float"] -> "number"
      ["Boolean"] -> "boolean"
      parts -> last_part(parts)
    end
  end

  defp last_part([part]), do: part
  defp last_part([_ | parts]), do: last_part(parts)
end
