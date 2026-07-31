defmodule NetworkDefense.Nodes.Service do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :name, :string
    field :protocol, Ecto.Enum, values: [:tcp, :udp]
    field :port, :integer
    field :version, :string
  end

  def default_data, do: %{name: "New service", protocol: "tcp", port: 80, version: nil}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:name, :protocol, :port, :version])
    |> validate_required([:name, :protocol, :port])
    |> validate_number(:port, greater_than: 0, less_than_or_equal_to: 65_535)
  end
end
