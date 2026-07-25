defmodule NetworkDefense.PortRange do
  @moduledoc false

  import Ecto.Changeset

  def validate(changeset) do
    case {get_field(changeset, :port_start), get_field(changeset, :port_end)} do
      {nil, nil} -> changeset
      {nil, _port_end} -> missing_port_boundary(changeset)
      {_port_start, nil} -> missing_port_boundary(changeset)
      {_port_start, _port_end} -> validate_interval(changeset)
    end
  end

  defp missing_port_boundary(changeset) do
    add_error(changeset, :port_start, "both port_start and port_end must be provided together")
  end

  defp validate_interval(changeset) do
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
