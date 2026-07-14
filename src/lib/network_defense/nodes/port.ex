defmodule NetworkDefense.Graph.Nodes.Port do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :port, :integer
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:port])
    |> validate_required([:port])
    |> validate_number(:port, greater_or_equal_than: 0)
  end
end
