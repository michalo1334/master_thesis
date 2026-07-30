defmodule Mix.Tasks.Gen.Contracts.EnumValues do
  @moduledoc false

  alias Mix.Tasks.Gen.Contracts.{Handler, Renderer}
  @behaviour Handler

  @impl true
  def render(%{metadata: %{enum_values: values}} = context) do
    overrides =
      Map.new(values, fn {field, atoms} ->
        {field, enum_type(atoms)}
      end)

    {:emit, Renderer.interface(context.ts_name, context.fields, overrides)}
  end

  def render(_context), do: :skip

  defp enum_type(atoms) do
    values = Enum.map(atoms, &"\"#{&1}\"")
    inline = Enum.join(values, " | ")

    if String.length(inline) > 72 do
      "\n    | " <> Enum.join(values, "\n    | ")
    else
      inline
    end
  end
end
