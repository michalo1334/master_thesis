defmodule NetworkDefense.Nodes.Host do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :name, :string
  end

  def default_data, do: %{name: "New host"}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end
