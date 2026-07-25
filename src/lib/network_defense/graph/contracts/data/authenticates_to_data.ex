defmodule NetworkDefense.Graph.Contracts.Data.AuthenticatesToData do
  @moduledoc false

  use NetworkDefense.Contracts, category: :graph

  @enum_values granted_privilege: [:user, :administrator]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :granted_privilege, :string
  end

  @type t :: %__MODULE__{
          granted_privilege: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:granted_privilege])
    |> validate_required([:granted_privilege])
    |> validate_inclusion(:granted_privilege, ["user", "administrator"])
  end
end
