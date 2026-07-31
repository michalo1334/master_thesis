defmodule NetworkDefense.Nodes.Credential do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :identifier, :string
    field :credential_type, Ecto.Enum, values: [:password, :ssh_key, :token]
  end

  def default_data, do: %{identifier: "New credential", credential_type: "password"}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:identifier, :credential_type])
    |> validate_required([:identifier, :credential_type])
  end
end
