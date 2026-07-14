defmodule NetworkDefense.Relationships.GrantsCapability do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :kind, Ecto.Enum, values: [:command_execution, :root_access]
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:kind])
    |> validate_required([:kind])
  end
end
