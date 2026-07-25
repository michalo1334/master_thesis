defmodule NetworkDefense.Graph.Contracts.Data.CredentialData do
  @moduledoc false

  use NetworkDefense.Contracts, category: :graph

  @enum_values credential_type: [:password, :ssh_key, :token]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :identifier, :string
    field :credential_type, :string
  end

  @type t :: %__MODULE__{
          identifier: String.t(),
          credential_type: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:identifier, :credential_type])
    |> validate_required([:identifier, :credential_type])
    |> validate_inclusion(:credential_type, ["password", "ssh_key", "token"])
  end
end
