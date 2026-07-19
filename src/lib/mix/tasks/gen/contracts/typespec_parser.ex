defmodule Mix.Tasks.Gen.Contracts.TypespecParser do
  @moduledoc false

  def parse(module) do
    {:ok, types} = Code.Typespec.fetch_types(module)

    Enum.find_value(types, fn
      {:type, {:t, ast, _}} ->
        extract_fields(ast)

      _ ->
        nil
    end) || raise "no @type t found in #{inspect(module)}"
  end

  def variants_for_field(fields, data_field) do
    {^data_field, type_ast} = List.keyfind(fields, data_field, 0)
    Mix.Tasks.Gen.Contracts.Renderer.union_modules(type_ast)
  end

  defp extract_fields({:type, _, :map, fields}) do
    Enum.map(fields, fn
      {:type, _, :map_field_exact, [{:atom, _, :__struct__}, _]} ->
        nil

      {:type, _, :map_field_exact, [{:atom, _, field_name}, type]} ->
        {field_name, type}

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_fields(ast) do
    raise "unexpected typespec ast: #{inspect(ast)}"
  end
end
