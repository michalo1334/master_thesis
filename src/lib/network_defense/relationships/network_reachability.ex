defmodule NetworkDefense.Relationships.NetworkReachability do
  use Ecto.Schema
  import Ecto.Changeset

  alias NetworkDefense.Nodes.Service

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
    |> validate_ports()
  end

  def matches_service?(%__MODULE__{} = reachability, %Service{} = service) do
    (reachability.protocol == :any or reachability.protocol == service.protocol) and
      (is_nil(reachability.port_start) or
         (service.port >= reachability.port_start and service.port <= reachability.port_end))
  end

  defp validate_ports(changeset) do
    case {get_field(changeset, :port_start), get_field(changeset, :port_end)} do
      {nil, nil} -> changeset
      {nil, _port_end} -> missing_port_boundary(changeset)
      {_port_start, nil} -> missing_port_boundary(changeset)
      {_port_start, _port_end} -> validate_port_interval(changeset)
    end
  end

  defp missing_port_boundary(changeset),
    do:
      add_error(changeset, :port_start, "both port_start and port_end must be provided together")

  defp validate_port_interval(changeset) do
    changeset
    |> validate_number(:port_start, greater_than: 0, less_than_or_equal_to: 65_535)
    |> validate_number(:port_end, greater_than: 0, less_than_or_equal_to: 65_535)
    |> validate_interval_order()
  end

  defp validate_interval_order(changeset) do
    if get_field(changeset, :port_start) > get_field(changeset, :port_end) do
      add_error(changeset, :port_start, "must be less than or equal to port_end")
    else
      changeset
    end
  end
end
