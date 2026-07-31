defmodule NetworkDefense.Relationships.StoresCredential do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :required_privilege, Ecto.Enum, values: [:user, :administrator]
  end

  def default_data, do: %{required_privilege: "user"}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:required_privilege])
    |> validate_required([:required_privilege])
  end
end
