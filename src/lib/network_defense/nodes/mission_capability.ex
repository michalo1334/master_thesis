defmodule NetworkDefense.Nodes.MissionCapability do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :name, :string
    field :description, :string
    field :impact_weight, :float, default: 1.0
    field :min_operational_support, :integer, default: 1
  end

  def default_data do
    %{name: "New mission capability", impact_weight: 1.0, min_operational_support: 1}
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:name, :description, :impact_weight, :min_operational_support])
    |> validate_required([:name, :impact_weight, :min_operational_support])
    |> validate_number(:impact_weight, greater_than: 0)
    |> validate_number(:min_operational_support, greater_than: 0)
  end
end
