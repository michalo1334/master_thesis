defmodule NetworkDefense.Relationships.SegmentReachability do
  use Ecto.Schema
  import Ecto.Changeset

  alias NetworkDefense.PortRange

  @primary_key false

  embedded_schema do
    field :protocol, Ecto.Enum, values: [:tcp, :udp, :any], default: :any
    field :port_start, :integer
    field :port_end, :integer
  end

  def default_data, do: %{protocol: "any", port_start: nil, port_end: nil}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:protocol, :port_start, :port_end])
    |> validate_required([:protocol])
    |> PortRange.validate()
  end
end
