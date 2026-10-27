defmodule NetworkDefense.Graph.Data do
  @moduledoc false

  import Ecto.Changeset,
    only: [
      add_error: 3,
      apply_action: 2,
      cast: 3,
      cast_embed: 2,
      cast_embed: 3,
      get_field: 2,
      validate_change: 3,
      validate_number: 3,
      validate_required: 2
    ]

  alias NetworkDefense.NetworkCidr

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

  def vulnerability_changeset(schema, attrs) do
    schema
    |> cast(attrs, [:identifier, :exploit_probability])
    |> cast_embed(:cvss, required: true)
    |> validate_required([:identifier, :exploit_probability])
    |> validate_number(:exploit_probability,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1
    )
  end

  def network_segment_changeset(schema, attrs) do
    schema
    |> cast(attrs, [:name, :cidr])
    |> validate_required([:name])
    |> validate_change(:cidr, fn :cidr, cidr ->
      if is_nil(cidr) or NetworkCidr.valid?(cidr), do: [], else: [cidr: "must be a valid CIDR"]
    end)
  end

  def mission_capability_changeset(schema, attrs) do
    schema
    |> cast(attrs, [:name, :description, :impact_weight, :min_operational_support])
    |> cast_embed(:required_flows)
    |> validate_required([:name, :impact_weight, :min_operational_support])
    |> validate_number(:impact_weight, greater_than: 0)
    |> validate_number(:min_operational_support, greater_than: 0)
  end

  defp value_param(nil), do: nil
  defp value_param(value) when is_atom(value), do: Atom.to_string(value)
  defp value_param(value) when is_struct(value), do: to_params(value)

  defp value_param(value) when is_map(value),
    do: Map.new(value, fn {key, value} -> {key, value_param(value)} end)

  defp value_param(value) when is_list(value), do: Enum.map(value, &value_param/1)
  defp value_param(value), do: value
end
