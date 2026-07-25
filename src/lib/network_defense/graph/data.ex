defmodule NetworkDefense.Graph.Data do
  @moduledoc false

  import Ecto.Changeset, only: [apply_action: 2]

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

  defp value_param(nil), do: nil
  defp value_param(value) when is_atom(value), do: Atom.to_string(value)
  defp value_param(value), do: value
end
