defmodule Mix.Tasks.Gen.Contracts.EnumValues do
  @moduledoc false

  alias Mix.Tasks.Gen.Contracts.{Handler, Renderer}
  @behaviour Handler

  @impl true
  def render(%{metadata: %{enum_values: values}} = context) do
    aliases = Map.get(context.metadata, :enum_type_aliases, %{})

    overrides =
      Map.new(values, fn {field, atoms} ->
        {field, Map.get(aliases, field) || enum_type(field, atoms)}
      end)

    enum_fields = Enum.map_join(values, ", ", fn {field, _} -> field end)
    comment = Renderer.source_comment(context.module, "enum fields: #{enum_fields}")

    {:emit, "#{comment}\n#{Renderer.interface(context.module, context.fields, overrides)}"}
  end

  def render(_context), do: :skip

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
end
