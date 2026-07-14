defmodule NetworkDefense.Relationships.ListensOn do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> validate_required([])
  end
end
