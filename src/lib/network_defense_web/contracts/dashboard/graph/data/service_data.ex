defmodule NetworkDefenseWeb.Web.Contracts.Data.ServiceData do
  @moduledoc false

  use NetworkDefenseWeb.Contracts

  @enum_values protocol: [:tcp, :udp]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :name, :string
    field :protocol, :string
    field :port, :integer
    field :version, :string
  end

  @type t :: %__MODULE__{
          name: String.t(),
          protocol: String.t(),
          port: integer(),
          version: String.t() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:name, :protocol, :port, :version])
    |> validate_required([:name, :protocol, :port])
    |> validate_inclusion(:protocol, ["tcp", "udp"])
    |> validate_number(:port, greater_than: 0, less_than_or_equal_to: 65_535)
  end
end
