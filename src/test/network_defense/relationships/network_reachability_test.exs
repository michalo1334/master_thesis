defmodule NetworkDefense.Relationships.NetworkReachabilityTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Relationships.NetworkReachability

  test "is an empty operational marker that ignores protocol and port attributes" do
    assert {:ok, _} = validate(%{})
    assert {:ok, _} = validate(%{"protocol" => "tcp", "port_start" => 80})
    assert {:ok, _} = validate(%{"protocol" => "udp", "port_start" => 443, "port_end" => 80})
  end

  defp validate(attrs) do
    %NetworkReachability{}
    |> NetworkReachability.changeset(attrs)
    |> Ecto.Changeset.apply_action(:validate)
  end
end
