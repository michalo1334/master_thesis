defmodule NetworkDefense.Nodes.NetworkSegment do
  use Ecto.Schema

  alias NetworkDefense.Nodes.Validation

  @primary_key false

  embedded_schema do
    field :name, :string
    field :cidr, :string
  end

  def default_data, do: %{name: "New segment", cidr: nil}

  def changeset(schema, attrs), do: Validation.network_segment_changeset(schema, attrs)
end
