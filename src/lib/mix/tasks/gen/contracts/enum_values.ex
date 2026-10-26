defmodule Mix.Tasks.Gen.Contracts.EnumValues do
  @moduledoc false

  alias Mix.Tasks.Gen.Contracts.{Handler, Renderer}
  @behaviour Handler

  @impl true
  def render(%{metadata: %{enum_values: values}} = context) do
    aliases = Map.get(context.metadata, :enum_type_aliases, %{})
    fields = Map.new(context.fields)

    overrides =
      Map.new(values, fn {field, atoms} ->
        {field, Map.get(aliases, field) || enum_override(field, atoms, fields)}
      end)

    enum_fields = Enum.map_join(values, ", ", fn {field, _} -> field end)
    comment = Renderer.source_comment(context.module, "enum fields: #{enum_fields}")

    {:emit, "#{comment}\n#{Renderer.interface(context.module, context.fields, overrides)}"}
  end

  def render(_context), do: :skip

  # A closed set that the schema declares as a list of values renders as a union
  # of string literals inside one array type.
  defp enum_override(field, atoms, fields) do
    if list?(fields, field),
      do: enum_array_type(field, atoms),
      else: enum_type(field, atoms)
  end

  defp list?(fields, field) do
    case Map.fetch(fields, field) do
      {:ok, {:type, _, :list, [_item]}} -> true
      _absent_or_scalar -> false
    end
  end

  defp enum_type(field, atoms) do
    values = Enum.map(atoms, &"\"#{&1}\"")
    inline = Enum.join(values, " | ")

    cond do
      String.length("    #{inline};") > 80 ->
        "\n    | " <> Enum.join(values, "\n    | ")

      String.length("  #{field}: #{inline};") > 80 ->
        "\n    #{inline}"

      true ->
        inline
    end
  end

  defp enum_array_type(field, atoms) do
    inline = Enum.map_join(atoms, " | ", &"\"#{&1}\"")
    joined = "Array<#{inline}>"

    if String.length("  #{field}: #{joined};") > 80 do
      "\n    Array<\n      #{inline}\n    >"
    else
      joined
    end
  end
end
