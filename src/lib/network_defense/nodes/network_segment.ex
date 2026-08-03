defmodule NetworkDefense.Nodes.NetworkSegment do
  use Ecto.Schema
  import Ecto.Changeset
  alias NetworkDefense.NetworkCidr

  @primary_key false

  embedded_schema do
    field :name, :string
    field :cidr, :string
  end

  def default_data, do: %{name: "New segment", cidr: nil}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:name, :cidr])
    |> validate_required([:name])
    |> validate_change(:cidr, fn :cidr, cidr ->
      if is_nil(cidr) or NetworkCidr.valid?(cidr), do: [], else: [cidr: "must be a valid CIDR"]
    end)
  end
end
