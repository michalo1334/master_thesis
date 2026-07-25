defmodule NetworkDefense.Relationships.NetworkReachability do
  use Ecto.Schema
  import Ecto.Changeset

  alias NetworkDefense.Nodes.Service
  alias NetworkDefense.PortRange

  @primary_key false

  embedded_schema do
    field :protocol, Ecto.Enum, values: [:tcp, :udp, :any], default: :any
    field :port_start, :integer
    field :port_end, :integer
  end

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:protocol, :port_start, :port_end])
    |> validate_required([:protocol])
    |> PortRange.validate()
  end

  def matches_service?(%__MODULE__{} = reachability, %Service{} = service) do
    (reachability.protocol == :any or reachability.protocol == service.protocol) and
      (is_nil(reachability.port_start) or
         (service.port >= reachability.port_start and service.port <= reachability.port_end))
  end
end
