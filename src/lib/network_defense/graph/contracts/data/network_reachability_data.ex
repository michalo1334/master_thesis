defmodule NetworkDefense.Graph.Contracts.Data.NetworkReachabilityData do
  @moduledoc false

  use NetworkDefense.Contracts, category: :graph

  alias NetworkDefense.PortRange

  @enum_values protocol: [:tcp, :udp, :any]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :protocol, :string
    field :port_start, :integer
    field :port_end, :integer
  end

  @type t :: %__MODULE__{
          protocol: String.t(),
          port_start: integer() | nil,
          port_end: integer() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:protocol, :port_start, :port_end])
    |> validate_required([:protocol])
    |> validate_inclusion(:protocol, ["tcp", "udp", "any"])
    |> PortRange.validate()
  end
end
