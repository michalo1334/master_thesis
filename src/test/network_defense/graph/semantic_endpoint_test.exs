defmodule NetworkDefense.Graph.SemanticEndpointTest do
  use NetworkDefense.DataCase, async: true

  alias NetworkDefense.Graph.{Edge, Graph, Graphs, Node}
  alias NetworkDefense.Nodes.{Host, MissionCapability, NetworkSegment, Service}
  alias NetworkDefense.Relationships.{Contains, NetworkReachability, Runs, Supports}

  test "accepts valid directed endpoints" do
    graph = Graph.new("Topology")
    host = node(graph, Host, %{"name" => "host"})
    service = node(graph, Service, %{"name" => "ssh", "protocol" => "tcp", "port" => 22})

    assert [_] =
             graph
             |> Graph.add_node(host)
             |> Graph.add_node(service)
             |> Graph.add_edge(host, service, %{
               type: Atom.to_string(NetworkReachability),
               data: %{}
             })
             |> Graph.edges()
  end

  test "rejects invalid directed endpoints" do
    graph = Graph.new("Topology")
    first = node(graph, Service, %{"name" => "first", "protocol" => "tcp", "port" => 22})
    second = node(graph, Service, %{"name" => "second", "protocol" => "tcp", "port" => 443})
    graph = graph |> Graph.add_node(first) |> Graph.add_node(second)

    assert_raise ArgumentError, ~r/not valid/, fn ->
      Graph.add_edge(graph, first, second, %{type: Atom.to_string(Runs), data: %{}})
    end
  end

  test "accepts segment containment and rejects multiple segments per host" do
    graph = Graph.new("Topology")
    host = node(graph, Host, %{"name" => "host"})
    dmz = node(graph, NetworkSegment, %{"name" => "DMZ"})
    internal = node(graph, NetworkSegment, %{"name" => "Internal"})

    assert {:error, :multiple_segments} =
             Graph.hydrate(
               graph,
               [host, dmz, internal],
               [
                 Edge.new(graph.id, dmz.id, host.id, %{type: Atom.to_string(Contains), data: %{}}),
                 Edge.new(graph.id, internal.id, host.id, %{
                   type: Atom.to_string(Contains),
                   data: %{}
                 })
               ]
             )

    graph = graph |> Graph.add_node(host) |> Graph.add_node(dmz) |> Graph.add_node(internal)
    graph = Graph.add_edge(graph, dmz, host, %{type: Atom.to_string(Contains), data: %{}})

    assert_raise ArgumentError, ~r/already belongs/, fn ->
      Graph.add_edge(graph, internal, host, %{type: Atom.to_string(Contains), data: %{}})
    end
  end

  test "hydrates invalid semantic endpoints as an error" do
    graph = Graph.new("Topology")
    first = node(graph, Service, %{"name" => "first", "protocol" => "tcp", "port" => 22})
    second = node(graph, Service, %{"name" => "second", "protocol" => "tcp", "port" => 443})

    assert {:error, :invalid_endpoints} =
             Graph.hydrate(
               graph,
               [first, second],
               [Edge.new(graph.id, first.id, second.id, %{type: Atom.to_string(Runs), data: %{}})]
             )
  end

  test "rejects operational reachability edges before appending a revision" do
    assert {:ok, graph} = Graphs.insert(Graph.new("Topology"))
    host_id = Ecto.UUID.generate()

    attrs = %{
      "title" => "Topology",
      "revision_id" => graph.revision_id,
      "nodes" => [node_attrs(host_id, Host, %{"name" => "host"})],
      "edges" => [
        %{
          "id" => Ecto.UUID.generate(),
          "from_id" => host_id,
          "to_id" => host_id,
          "type" => Atom.to_string(NetworkReachability),
          "data" => %{}
        }
      ]
    }

    assert {:error, :invalid_edge} = Graphs.replace(graph.id, attrs)
    assert %{revision_number: 1} = Graphs.load_revision!(graph.revision_id)
  end

  test "requires each mission capability to have enough distinct supports" do
    graph = Graph.new("Topology")
    host = node(graph, Host, %{"name" => "host"})
    segment = node(graph, NetworkSegment, %{"name" => "DMZ"})

    capability =
      node(graph, MissionCapability, %{
        "name" => "Order processing",
        "impact_weight" => 5.0,
        "min_operational_support" => 2
      })

    edges = [
      Edge.new(graph.id, segment.id, host.id, %{type: Atom.to_string(Contains), data: %{}}),
      Edge.new(graph.id, host.id, capability.id, %{type: Atom.to_string(Supports), data: %{}})
    ]

    assert {:error, :invalid_mission_capability_support} =
             Graph.hydrate(graph, [segment, host, capability], edges)
  end

  test "accepts enough distinct supports and rejects duplicate supports" do
    graph = Graph.new("Topology")
    primary = node(graph, Host, %{"name" => "primary"})
    replica = node(graph, Host, %{"name" => "replica"})
    segment = node(graph, NetworkSegment, %{"name" => "DMZ"})

    capability =
      node(graph, MissionCapability, %{
        "name" => "Order processing",
        "impact_weight" => 5.0,
        "min_operational_support" => 2
      })

    edges = [
      Edge.new(graph.id, segment.id, primary.id, %{type: Atom.to_string(Contains), data: %{}}),
      Edge.new(graph.id, segment.id, replica.id, %{type: Atom.to_string(Contains), data: %{}}),
      Edge.new(graph.id, primary.id, capability.id, %{type: Atom.to_string(Supports), data: %{}}),
      Edge.new(graph.id, replica.id, capability.id, %{type: Atom.to_string(Supports), data: %{}})
    ]

    assert {:ok, _graph} = Graph.hydrate(graph, [segment, primary, replica, capability], edges)

    duplicate =
      Edge.new(graph.id, primary.id, capability.id, %{type: Atom.to_string(Supports), data: %{}})

    assert {:error, :invalid_mission_capability_support} =
             Graph.hydrate(graph, [segment, primary, replica, capability], [duplicate | edges])
  end

  test "accepts required flows referencing a segment and a service in the graph" do
    graph = Graph.new("Topology")
    host = node(graph, Host, %{"name" => "host"})
    segment = node(graph, NetworkSegment, %{"name" => "DMZ"})
    service = node(graph, Service, %{"name" => "ssh", "protocol" => "tcp", "port" => 22})

    capability =
      node(graph, MissionCapability, %{
        "name" => "Order processing",
        "impact_weight" => 5.0,
        "min_operational_support" => 1,
        "required_flows" => [
          %{
            "source_segment_id" => segment.id,
            "target_service_id" => service.id
          }
        ]
      })

    edges = [
      Edge.new(graph.id, segment.id, host.id, %{type: Atom.to_string(Contains), data: %{}}),
      Edge.new(graph.id, host.id, service.id, %{type: Atom.to_string(Runs), data: %{}}),
      Edge.new(graph.id, host.id, capability.id, %{type: Atom.to_string(Supports), data: %{}})
    ]

    assert {:ok, _graph} = Graph.hydrate(graph, [segment, host, service, capability], edges)
  end

  test "rejects required flows referencing a missing segment or service" do
    graph = Graph.new("Topology")
    host = node(graph, Host, %{"name" => "host"})
    segment = node(graph, NetworkSegment, %{"name" => "DMZ"})
    service = node(graph, Service, %{"name" => "ssh", "protocol" => "tcp", "port" => 22})

    capability =
      node(graph, MissionCapability, %{
        "name" => "Order processing",
        "impact_weight" => 5.0,
        "min_operational_support" => 1,
        "required_flows" => [
          %{
            "source_segment_id" => Ecto.UUID.generate(),
            "target_service_id" => service.id
          }
        ]
      })

    edges = [
      Edge.new(graph.id, segment.id, host.id, %{type: Atom.to_string(Contains), data: %{}}),
      Edge.new(graph.id, host.id, service.id, %{type: Atom.to_string(Runs), data: %{}}),
      Edge.new(graph.id, host.id, capability.id, %{type: Atom.to_string(Supports), data: %{}})
    ]

    assert {:error, :invalid_required_flow_reference} =
             Graph.hydrate(graph, [segment, host, service, capability], edges)

    missing_target =
      node(graph, MissionCapability, %{
        "name" => "Order processing",
        "impact_weight" => 5.0,
        "min_operational_support" => 1,
        "required_flows" => [
          %{
            "source_segment_id" => segment.id,
            "target_service_id" => Ecto.UUID.generate()
          }
        ]
      })

    missing_target_edges = [
      Edge.new(graph.id, segment.id, host.id, %{type: Atom.to_string(Contains), data: %{}}),
      Edge.new(graph.id, host.id, service.id, %{type: Atom.to_string(Runs), data: %{}}),
      Edge.new(graph.id, host.id, missing_target.id, %{type: Atom.to_string(Supports), data: %{}})
    ]

    assert {:error, :invalid_required_flow_reference} =
             Graph.hydrate(graph, [segment, host, service, missing_target], missing_target_edges)
  end

  test "rejects required flows referencing nodes of the wrong type" do
    graph = Graph.new("Topology")
    host = node(graph, Host, %{"name" => "host"})
    segment = node(graph, NetworkSegment, %{"name" => "DMZ"})
    service = node(graph, Service, %{"name" => "ssh", "protocol" => "tcp", "port" => 22})

    wrong_source =
      node(graph, MissionCapability, %{
        "name" => "Order processing",
        "impact_weight" => 5.0,
        "min_operational_support" => 1,
        "required_flows" => [
          %{
            "source_segment_id" => host.id,
            "target_service_id" => service.id
          }
        ]
      })

    edges = [
      Edge.new(graph.id, segment.id, host.id, %{type: Atom.to_string(Contains), data: %{}}),
      Edge.new(graph.id, host.id, service.id, %{type: Atom.to_string(Runs), data: %{}}),
      Edge.new(graph.id, host.id, wrong_source.id, %{type: Atom.to_string(Supports), data: %{}})
    ]

    assert {:error, :invalid_required_flow_reference} =
             Graph.hydrate(graph, [segment, host, service, wrong_source], edges)

    wrong_target =
      node(graph, MissionCapability, %{
        "name" => "Order processing",
        "impact_weight" => 5.0,
        "min_operational_support" => 1,
        "required_flows" => [
          %{
            "source_segment_id" => segment.id,
            "target_service_id" => segment.id
          }
        ]
      })

    wrong_target_edges = [
      Edge.new(graph.id, segment.id, host.id, %{type: Atom.to_string(Contains), data: %{}}),
      Edge.new(graph.id, host.id, service.id, %{type: Atom.to_string(Runs), data: %{}}),
      Edge.new(graph.id, host.id, wrong_target.id, %{type: Atom.to_string(Supports), data: %{}})
    ]

    assert {:error, :invalid_required_flow_reference} =
             Graph.hydrate(graph, [segment, host, service, wrong_target], wrong_target_edges)
  end

  defp node(graph, type, data) do
    Node.new(graph.id, %{
      type: Atom.to_string(type),
      data: data,
      view_data: %{"x_pos" => 0, "y_pos" => 0}
    })
  end

  defp node_attrs(id, type, data) do
    %{
      "id" => id,
      "type" => Atom.to_string(type),
      "data" => data,
      "view_data" => %{"x_pos" => 0, "y_pos" => 0}
    }
  end
end
