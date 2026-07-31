defmodule NetworkDefense.Graph.DraftTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Graph.{Edge, Node}

  test "node draft uses the selected type defaults" do
    assert {:ok, node} = Node.draft("Service", %{x_pos: 30, y_pos: 40})

    assert %{
             type: "Service",
             data: %{name: "New service", protocol: "tcp", port: 80, version: nil},
             view_data: %{x_pos: 30.0, y_pos: 40.0}
           } = node
  end

  test "edge draft uses relationship defaults for valid directed endpoints" do
    host = %{id: Ecto.UUID.generate(), type: "Host"}
    service = %{id: Ecto.UUID.generate(), type: "Service"}
    host_id = host.id
    service_id = service.id

    assert {:ok, edge} = Edge.draft("NetworkReachability", host, service)

    assert %{
             type: "NetworkReachability",
             from_id: ^host_id,
             to_id: ^service_id,
             data: %{protocol: "any", port_start: nil, port_end: nil}
           } = edge
  end

  test "edge draft rejects invalid directed endpoints" do
    service = %{id: Ecto.UUID.generate(), type: "Service"}
    host = %{id: Ecto.UUID.generate(), type: "Host"}

    assert :error = Edge.draft("Runs", service, host)
  end
end
