defmodule NetworkDefense.Relationships.AuthenticatesTo do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :granted_privilege, Ecto.Enum, values: [:user, :administrator]
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:granted_privilege])
    |> validate_required([:granted_privilege])
  end
end
