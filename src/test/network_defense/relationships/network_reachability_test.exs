defmodule NetworkDefense.Relationships.NetworkReachabilityTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Relationships.NetworkReachability

  test "validates complete port intervals" do
    assert {:ok, _} = validate(%{"protocol" => "tcp", "port_start" => 80, "port_end" => 443})
    assert {:error, _} = validate(%{"protocol" => "tcp", "port_start" => 80})
    assert {:error, _} = validate(%{"protocol" => "tcp", "port_start" => 443, "port_end" => 80})
  end

  defp validate(attrs) do
    %NetworkReachability{}
    |> NetworkReachability.changeset(attrs)
    |> Ecto.Changeset.apply_action(:validate)
  end
end
