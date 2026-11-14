defmodule NetworkDefense.Nodes.Validation do
  @moduledoc false

  import Ecto.Changeset,
    only: [
      cast: 3,
      cast_embed: 2,
      cast_embed: 3,
      validate_change: 3,
      validate_number: 3,
      validate_required: 2
    ]

  alias NetworkDefense.NetworkCidr

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
end
