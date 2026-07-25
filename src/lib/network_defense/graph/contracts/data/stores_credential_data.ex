defmodule NetworkDefense.Graph.Contracts.Data.StoresCredentialData do
  @moduledoc false

  use NetworkDefense.Contracts, category: :graph

  @enum_values required_privilege: [:user, :administrator]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :required_privilege, :string
  end

  @type t :: %__MODULE__{
          required_privilege: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:required_privilege])
    |> validate_required([:required_privilege])
    |> validate_inclusion(:required_privilege, ["user", "administrator"])
  end
end
