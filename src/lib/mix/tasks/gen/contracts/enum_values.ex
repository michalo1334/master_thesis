defmodule Mix.Tasks.Gen.Contracts.EnumValues do
  @moduledoc false

  alias Mix.Tasks.Gen.Contracts.{Handler, Renderer}
  @behaviour Handler

  @impl true
  def render(%{metadata: %{enum_values: values}} = context) do
    overrides =
      Map.new(values, fn {field, atoms} ->
        {field, Enum.map_join(atoms, " | ", &"\"#{&1}\"")}
      end)

    {:emit, Renderer.interface(context.ts_name, context.fields, overrides)}
  end

  def render(_context), do: :skip
end
