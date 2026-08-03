defmodule Mix.Tasks.Gen.Contracts.Discriminant do
  @moduledoc false

  alias Mix.Tasks.Gen.Contracts.{Handler, Renderer, TypespecParser}
  @behaviour Handler

  @impl true
  def render(%{metadata: %{discriminant: config}} = context) do
    field = Keyword.fetch!(config, :field)
    data_field = Keyword.fetch!(config, :data_field)
    variants = Keyword.fetch!(config, :variants)

    validate_variants!(context.fields, data_field, variants)

    fields = Enum.reject(context.fields, fn {name, _type} -> name in [field, data_field] end)
    variant_names = Enum.map(variants, fn {tag, _module} -> "#{tag}#{context.ts_name}" end)
    type_declaration = union_declaration(context.ts_name, variant_names)

    interfaces =
      Enum.map(variants, fn {tag, module} ->
        overrides = %{field => "\"#{tag}\"", data_field => Renderer.type(remote_type(module))}

        properties = [
          Renderer.property(field, nil, overrides[field]),
          Renderer.property(data_field, nil, overrides[data_field])
        ]

        properties =
          properties ++ Enum.map(fields, fn {name, type} -> Renderer.property(name, type) end)

        "export interface #{tag}#{context.ts_name} {\n#{Enum.join(properties, "\n")}\n}"
      end)

    {:emit, "#{type_declaration}\n\n#{Enum.join(interfaces, "\n\n")}"}
  end

  def render(_context), do: :skip

  defp validate_variants!(fields, data_field, variants) do
    expected = fields |> TypespecParser.variants_for_field(data_field) |> MapSet.new()
    configured = variants |> Keyword.values() |> MapSet.new()

    if expected != configured do
      raise "discriminant variants do not match the #{data_field} typespec"
    end
  end

  defp remote_type(module) do
    {:remote_type, 0, [{:atom, 0, module}, {:atom, 0, :t}, []]}
  end

  defp union_declaration(name, variants) do
    joined = Enum.join(variants, " | ")
    single_line = "export type #{name} = #{joined};"

    if String.length(single_line) <= 80 do
      single_line
    else
      "export type #{name} =\n  | #{Enum.join(variants, "\n  | ")};"
    end
  end
end
