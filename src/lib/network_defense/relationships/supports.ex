defmodule NetworkDefense.Relationships.Supports do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
  end

  def default_data, do: %{}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> validate_required([])
  end
end
