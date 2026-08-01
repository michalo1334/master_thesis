defmodule NetworkDefense.Graph.Data do
  @moduledoc false

  import Ecto.Changeset, only: [add_error: 3, apply_action: 2, get_field: 2]

  def to_params(data) when is_struct(data) do
    data
    |> Map.from_struct()
    |> Map.drop([:__meta__])
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value_param(value)} end)
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  def load(schema, data) do
    schema
    |> struct()
    |> schema.changeset(data || %{})
    |> apply_action(:validate)
  end

  def validate_dynamic_data(changeset, registry) do
    case registry.module_for(get_field(changeset, :type)) do
      nil ->
        add_error(changeset, :type, "is invalid")

      schema ->
        if schema.changeset(struct(schema), get_field(changeset, :data) || %{}).valid? do
          changeset
        else
          add_error(changeset, :data, "is invalid")
        end
    end
  end

  defp value_param(nil), do: nil
  defp value_param(value) when is_atom(value), do: Atom.to_string(value)
  defp value_param(value) when is_struct(value), do: to_params(value)

  defp value_param(value) when is_map(value),
    do: Map.new(value, fn {key, value} -> {key, value_param(value)} end)

  defp value_param(value) when is_list(value), do: Enum.map(value, &value_param/1)
  defp value_param(value), do: value
end
