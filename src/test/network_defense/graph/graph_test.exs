defmodule NetworkDefense.Graph.GraphTest do
  use NetworkDefense.DataCase, async: true

  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.GraphDiff
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Nodes.Service
  alias NetworkDefense.Nodes.Vulnerability
  alias NetworkDefense.Relationships.HasVulnerability
  alias NetworkDefense.Relationships.NetworkReachability
  alias NetworkDefense.Relationships.Runs

  describe "new/1" do
    test "creates a graph with the given title" do
      graph = Graph.new("My Topology")
      assert graph.title == "My Topology"
      assert graph.tags == [:original]
      assert {:ok, _} = Ecto.UUID.cast(graph.id)
    end
  end

  describe "changeset" do
    test "validates title is present" do
      changeset = Graph.changeset(%Graph{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).title
    end

    test "validates title is non-empty" do
      changeset = Graph.changeset(%Graph{}, %{title: ""})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).title
    end

    test "accepts a valid title" do
      changeset = Graph.changeset(%Graph{}, %{title: "Valid Graph"})
      assert changeset.valid?
    end

    test "limits titles to the database length" do
      changeset = Graph.changeset(%Graph{}, %{title: String.duplicate("x", 256)})

      refute changeset.valid?
      assert "should be at most 255 character(s)" in errors_on(changeset).title
    end
  end

  describe "list_summaries/0" do
    test "returns empty list when no graphs exist" do
      delete_all_graphs()

      assert Graphs.list_summaries() == []
    end

    test "returns summaries with correct counts for graphs with nodes and edges" do
      delete_all_graphs()
      graph = insert_graph()
      source = insert_node(graph, "source")
      target = insert_service(graph, "target")
      insert_edge(source, target)

      summaries = Graphs.list_summaries()

      assert [summary] = summaries
      assert summary.id == graph.id
      assert summary.title == "test-graph"
      assert summary.parentId == nil
      assert summary.tags == ["original"]
      assert summary.nodeCount == 2
      assert summary.edgeCount == 1
    end

    test "returns summaries for multiple graphs" do
      delete_all_graphs()
      graph1 = insert_graph()
      graph2 = insert_graph()

      source1 = insert_node(graph1, "s1")
      target1 = insert_service(graph1, "t1")
      insert_edge(source1, target1)

      insert_node(graph2, "s2")
      insert_node(graph2, "i2")

      summaries = Graphs.list_summaries()
      assert [_, _] = summaries

      g1 = Enum.find(summaries, &(&1.id == graph1.id))
      assert g1.nodeCount == 2
      assert g1.edgeCount == 1

      g2 = Enum.find(summaries, &(&1.id == graph2.id))
      assert g2.nodeCount == 2
      assert g2.edgeCount == 0
    end
  end

  describe "persistence" do
    test "rejects a graph whose title exceeds the database length" do
      graph = Graph.new(String.duplicate("x", 256))

      assert {:error, {:graph, changeset}} = Graphs.insert(graph)
      assert "should be at most 255 character(s)" in errors_on(changeset).title
    end

    test "creates and loads a graph with typed nodes and edges" do
      graph = Graph.new("test-graph")
      source_host = build_node(graph, Host, %{"name" => "internet"})
      target_host = build_node(graph, Host, %{"name" => "web-01"})

      service =
        build_node(graph, Service, %{"name" => "nginx", "protocol" => "tcp", "port" => 443})

      vulnerability =
        build_node(graph, Vulnerability, %{
          "identifier" => "CVE-2024-0001",
          "cvss" => cvss(),
          "exploit_probability" => 0.8
        })

      reachability_edge =
        build_edge(graph, source_host, service, NetworkReachability, %{"protocol" => "any"})

      runs_edge = build_edge(graph, target_host, service, Runs)

      vulnerability_edge =
        build_edge(graph, service, vulnerability, HasVulnerability, %{
          "required_privilege" => "none",
          "granted_privilege" => "user"
        })

      graph =
        graph
        |> Graph.add_node(source_host)
        |> Graph.add_node(target_host)
        |> Graph.add_node(service)
        |> Graph.add_node(vulnerability)
        |> Graph.add_edge(reachability_edge)
        |> Graph.add_edge(runs_edge)
        |> Graph.add_edge(vulnerability_edge)

      assert {:ok, loaded_graph} = Graphs.insert(graph)

      assert Enum.sort(Enum.map(loaded_graph.nodes, & &1.id)) ==
               Enum.sort([source_host.id, target_host.id, service.id, vulnerability.id])

      assert [{service_id, %{id: reachability_edge_id}}] =
               Graph.outgoing(loaded_graph, source_host.id)

      assert service_id == service.id
      assert reachability_edge_id == reachability_edge.id

      assert [{runs_service_id, %{id: runs_edge_id}}] =
               Graph.outgoing(loaded_graph, target_host.id)

      assert runs_service_id == service.id
      assert runs_edge_id == runs_edge.id

      assert [{vulnerability_id, %{id: vulnerability_edge_id}}] =
               Graph.outgoing(loaded_graph, service.id)

      assert vulnerability_id == vulnerability.id
      assert vulnerability_edge_id == vulnerability_edge.id
    end
  end

  describe "clone/1" do
    test "creates an independent optimization graph with remapped edge endpoints" do
      source = Graph.new("source")
      host = build_node(source, Host, %{"name" => "source-host"})

      service =
        build_node(source, Service, %{
          "name" => "source-service",
          "protocol" => "tcp",
          "port" => 443
        })

      edge = build_edge(source, host, service, NetworkReachability, %{"protocol" => "any"})

      source = source |> Graph.add_node(host) |> Graph.add_node(service) |> Graph.add_edge(edge)
      clone = Graph.clone(source)

      assert clone.id != source.id
      assert clone.parent_id == source.id
      assert clone.source == :optimization
      assert clone.tags == [:optimization]
      assert clone.title == source.title

      assert MapSet.disjoint?(
               MapSet.new(Enum.map(source.nodes, & &1.id)),
               MapSet.new(Enum.map(clone.nodes, & &1.id))
             )

      assert MapSet.disjoint?(
               MapSet.new(Enum.map(Graph.edges(source), & &1.id)),
               MapSet.new(Enum.map(Graph.edges(clone), & &1.id))
             )

      [cloned_host, cloned_service] = clone.nodes
      [cloned_edge] = Graph.edges(clone)

      host = Node.hydrate!(host)
      service = Node.hydrate!(service)
      edge = Edge.hydrate!(edge)

      assert {cloned_host.type, cloned_host.data, cloned_host.view_data} ==
               {host.type, host.data, host.view_data}

      assert {cloned_service.type, cloned_service.data, cloned_service.view_data} ==
               {service.type, service.data, service.view_data}

      assert {cloned_edge.type, cloned_edge.data, cloned_edge.from_id, cloned_edge.to_id} ==
               {edge.type, edge.data, cloned_host.id, cloned_service.id}

      assert Graph.edges(Graph.remove_edge_by_id(clone, cloned_edge.id)) == []
      assert [^edge] = Graph.edges(source)
    end

    test "persists its lineage and survives deletion of its parent" do
      source = insert_graph()
      source = Graphs.load!(source.id)
      clone = Graph.clone(source)

      assert {:ok, clone} = Graphs.insert(clone)

      Repo.delete!(source)

      assert %{parent_id: nil, source: :optimization, tags: [:optimization]} =
               Graphs.load!(clone.id)
    end
  end

  describe "load/1" do
    test "loads an empty graph" do
      graph = insert_graph()

      loaded_graph = Graphs.load!(graph.id)

      assert loaded_graph.nodes == []
      assert loaded_graph.adjacency_list == %{}
    end

    test "loads all nodes and builds a directed adjacency list" do
      graph = insert_graph()
      source = insert_node(graph, "source")
      target = insert_service(graph, "target")
      isolated = insert_node(graph, "isolated")
      edge = insert_edge(source, target)

      loaded_graph = Graphs.load(graph.id)

      assert Enum.sort(Enum.map(loaded_graph.nodes, & &1.id)) ==
               Enum.sort([source.id, target.id, isolated.id])

      assert %{incoming: [], outgoing: [{target_id, loaded_edge}]} =
               loaded_graph.adjacency_list[source.id]

      assert target_id == target.id
      assert loaded_edge.id == edge.id

      assert %{incoming: [{source_id, incoming_edge}], outgoing: []} =
               loaded_graph.adjacency_list[target.id]

      assert source_id == source.id
      assert incoming_edge.id == edge.id
      assert loaded_graph.adjacency_list[isolated.id] == %{incoming: [], outgoing: []}
    end

    test "rejects edges whose other endpoint belongs to another graph" do
      graph = insert_graph()
      source = insert_node(graph, "source")

      other_graph = insert_graph()
      other_target = insert_node(other_graph, "other target")

      assert {:error, changeset} =
               %Edge{graph_id: graph.id, from_id: source.id, to_id: other_target.id}
               |> Edge.changeset(%{type: Atom.to_string(Runs)})
               |> Repo.insert()

      assert "does not exist" in errors_on(changeset).to_id
    end

    test "returns nil when the graph does not exist" do
      assert Graphs.load(Ecto.UUID.generate()) == nil
    end
  end

  describe "type validation" do
    test "accepts fully qualified registered module names" do
      node_changeset =
        Node.changeset(%Node{}, %{
          type: Atom.to_string(Host),
          data: %{"name" => "host"},
          view_data: %{"x_pos" => 0, "y_pos" => 0}
        })

      edge_changeset = Edge.changeset(%Edge{}, %{type: Atom.to_string(Runs), data: %{}})

      assert node_changeset.valid?
      assert edge_changeset.valid?
    end

    test "rejects unregistered module names" do
      changeset =
        Node.changeset(%Node{}, %{
          type: "Elixir.Unknown.Node",
          data: %{},
          view_data: %{"x_pos" => 0, "y_pos" => 0}
        })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).type
    end
  end

  describe "runtime hydration" do
    test "round-trips persisted nodes and edges through typed runtime values" do
      persisted_node = %Node{
        id: Ecto.UUID.generate(),
        graph_id: Ecto.UUID.generate(),
        type: Atom.to_string(Host),
        data: %{"name" => "host"},
        view_data: nil
      }

      assert {:ok, %Node{type: Host, data: %Host{name: "host"}} = node} =
               Node.hydrate(persisted_node)

      assert node.view_data == %{x_pos: 0, y_pos: 0, radius: nil}

      assert %Node{type: "Elixir.NetworkDefense.Nodes.Host", data: %{"name" => "host"}} =
               Node.persist(node)

      persisted_edge = %Edge{
        id: Ecto.UUID.generate(),
        graph_id: persisted_node.graph_id,
        from_id: persisted_node.id,
        to_id: Ecto.UUID.generate(),
        type: Atom.to_string(Runs),
        data: %{}
      }

      assert {:ok, %Edge{type: Runs, data: %Runs{}} = edge} = Edge.hydrate(persisted_edge)

      assert %Edge{type: "Elixir.NetworkDefense.Relationships.Runs", data: %{}} =
               Edge.persist(edge)
    end
  end

  describe "in-memory updates" do
    test "builds nodes and edges with UUIDs" do
      graph = Graph.new("test-graph")
      graph = Graph.add_node(graph, %{type: Atom.to_string(Host), data: %{"name" => "source"}})

      graph =
        Graph.add_node(graph, %{
          type: Atom.to_string(Service),
          data: %{"name" => "target", "protocol" => "tcp", "port" => 443}
        })

      [source, target] = graph.nodes

      graph = Graph.add_edge(graph, source, target, %{type: Atom.to_string(Runs), data: %{}})

      assert {:ok, _graph_id} = Ecto.UUID.cast(graph.id)
      assert {:ok, _source_id} = Ecto.UUID.cast(source.id)
      assert {:ok, _target_id} = Ecto.UUID.cast(target.id)
      assert [{target_id, %{id: edge_id}}] = Graph.outgoing(graph, source.id)
      assert target_id == target.id
      assert {:ok, _edge_id} = Ecto.UUID.cast(edge_id)
    end

    test "add and remove operations maintain the adjacency list" do
      graph = insert_graph()
      source = insert_node(graph, "source")
      target = insert_service(graph, "target")
      edge = insert_edge(source, target)

      graph =
        graph
        |> Graph.add_node(source)
        |> Graph.add_node(target)
        |> Graph.add_edge(edge)

      assert %{outgoing: [{target_id, added_edge}]} = graph.adjacency_list[source.id]
      assert target_id == target.id
      assert added_edge.id == edge.id

      assert %{incoming: [{source_id, incoming_edge}]} = graph.adjacency_list[target.id]
      assert source_id == source.id
      assert incoming_edge.id == edge.id

      graph = Graph.remove_edge_by_id(graph, edge.id)
      assert graph.adjacency_list[source.id] == %{incoming: [], outgoing: []}
      assert graph.adjacency_list[target.id] == %{incoming: [], outgoing: []}

      graph = Graph.remove_node_by_id(graph, target.id)
      refute Map.has_key?(graph.adjacency_list, target.id)
      refute Enum.any?(graph.nodes, &(&1.id == target.id))
    end

    test "rejects nodes and edges outside the graph" do
      graph = insert_graph()
      source = insert_node(graph, "source")

      other_graph = insert_graph()
      other_node = insert_node(other_graph, "other")

      graph = Graph.add_node(graph, source)

      assert_raise ArgumentError, fn -> Graph.add_node(graph, other_node) end

      invalid_edge = %Edge{
        graph_id: graph.id,
        from_id: source.id,
        to_id: other_node.id,
        type: Atom.to_string(Runs)
      }

      assert_raise ArgumentError, fn -> Graph.add_edge(graph, invalid_edge) end
      assert Map.keys(graph.adjacency_list) == [source.id]
    end
  end

  describe "complete graph replacement" do
    test "replaces the complete graph and increments its lock version" do
      graph = insert_graph()
      source = insert_node(graph, "source")
      target = insert_service(graph, "target")
      removed = insert_service(graph, "removed")
      old_edge = insert_edge(source, removed)
      edge_id = Ecto.UUID.generate()

      attrs = %{
        "title" => "replaced graph",
        "nodes" => [node_attrs(source), node_attrs(target)],
        "edges" => [
          edge_attrs(edge_id, source.id, target.id, NetworkReachability, %{"protocol" => "any"})
        ]
      }

      assert {:ok, %{graph: saved, diff: diff}} = Graphs.replace(graph.id, 1, attrs)
      assert saved.title == "replaced graph"
      assert saved.lock_version == 2
      assert Enum.sort(Enum.map(saved.nodes, & &1.id)) == Enum.sort([source.id, target.id])

      assert [%{id: ^edge_id, from_id: source_id, to_id: target_id, type: type}] =
               Graph.edges(saved)

      assert source_id == source.id
      assert target_id == target.id
      assert type == NetworkReachability

      for node <- saved.nodes do
        assert is_number(node.view_data.x_pos)
        assert is_number(node.view_data.y_pos)
      end

      assert diff.nodes.removed == [removed.id]
      assert diff.edges.removed == [old_edge.id]
      assert diff.edges.added == [edge_id]
    end

    test "does not rewrite or increment an unchanged graph" do
      graph = Graph.new("test-graph")
      node = build_node(graph, Host, %{"name" => "source"})
      graph = graph |> Graph.add_node(node)
      assert {:ok, graph} = Graphs.insert(graph)

      attrs = %{
        "title" => graph.title,
        "nodes" => [node_attrs(node)],
        "edges" => []
      }

      assert {:ok, %{graph: saved, diff: diff}} = Graphs.replace(graph.id, 1, attrs)
      assert GraphDiff.empty?(diff)
      assert saved.lock_version == 1
    end

    test "rejects a stale lock version without changing the graph" do
      graph = insert_graph()

      attrs = %{
        "title" => "first replacement",
        "nodes" => [],
        "edges" => []
      }

      assert {:ok, %{graph: saved}} = Graphs.replace(graph.id, 1, attrs)
      assert saved.lock_version == 2

      assert {:error, :stale} =
               Graphs.replace(graph.id, 1, %{attrs | "title" => "stale replacement"})

      assert Graphs.load!(graph.id).title == "first replacement"
    end

    test "rejects an invalid complete graph without partial writes" do
      graph = insert_graph()
      source = insert_node(graph, "source")

      attrs = %{
        "title" => "invalid replacement",
        "nodes" => [node_attrs(source)],
        "edges" => [edge_attrs(Ecto.UUID.generate(), source.id, Ecto.UUID.generate(), Runs)]
      }

      assert {:error, :invalid_graph} = Graphs.replace(graph.id, 1, attrs)
      persisted = Graphs.load!(graph.id)
      assert persisted.title == "test-graph"
      assert Enum.map(persisted.nodes, & &1.id) == [source.id]
      assert persisted.lock_version == 1
    end

    test "validates view_data for every node" do
      graph = insert_graph()
      source = insert_node(graph, "source")
      valid_node_attrs = node_attrs(source)

      invalid_nodes = [
        Map.delete(valid_node_attrs, "view_data"),
        %{valid_node_attrs | "view_data" => "not_a_map"},
        %{valid_node_attrs | "view_data" => %{"x" => 1, "y" => 2}},
        %{valid_node_attrs | "view_data" => %{"x_pos" => "abc", "y_pos" => 2}}
      ]

      Enum.each(invalid_nodes, fn invalid_node ->
        attrs = %{"title" => graph.title, "nodes" => [invalid_node], "edges" => []}
        assert {:error, :invalid_graph} = Graphs.replace(graph.id, 1, attrs)
      end)

      assert {:ok, _} =
               Graphs.replace(graph.id, 1, %{
                 "title" => graph.title,
                 "nodes" => [valid_node_attrs],
                 "edges" => []
               })
    end

    test "view-data-only replacement increments lock_version" do
      graph = insert_graph()
      node = insert_node(graph, "node")
      new_view_data = %{"x_pos" => 10, "y_pos" => 20}

      attrs = %{
        "title" => graph.title,
        "nodes" => [%{node_attrs(node) | "view_data" => new_view_data}],
        "edges" => []
      }

      assert {:ok, %{graph: saved, diff: diff}} = Graphs.replace(graph.id, 1, attrs)
      assert saved.lock_version == 2
      refute GraphDiff.empty?(diff)

      [saved_node] = saved.nodes
      assert saved_node.view_data.x_pos == new_view_data["x_pos"]
      assert saved_node.view_data.y_pos == new_view_data["y_pos"]
    end
  end

  describe "graph diff" do
    test "matches by stable IDs and includes view-data-only changes" do
      graph = Graph.new("graph")
      node = build_node(graph, Host, %{"name" => "source"})
      node_a = %{node | view_data: %{"x_pos" => 1, "y_pos" => 2}}
      node_b = %{node | view_data: %{"x_pos" => 3, "y_pos" => 2}}

      previous = graph |> Graph.add_node(node_a)
      candidate = Graph.update_node(previous, node_b)
      diff = GraphDiff.compare(previous, candidate)

      assert diff.nodes.changed == [%{id: node.id, fields: [:view_data]}]
      refute GraphDiff.empty?(diff)
    end

    test "reports changed node and edge fields" do
      graph = Graph.new("graph")
      source = build_node(graph, Host, %{"name" => "source"})

      target =
        build_node(graph, Service, %{"name" => "target", "protocol" => "tcp", "port" => 443})

      edge = build_edge(graph, source, target, Runs)

      previous = graph |> Graph.add_node(source) |> Graph.add_node(target) |> Graph.add_edge(edge)

      candidate =
        previous
        |> Graph.update_node(%{source | data: %{"name" => "renamed"}})
        |> Graph.update_edge(%{edge | type: Atom.to_string(NetworkReachability)})

      diff = GraphDiff.compare(previous, candidate)

      assert diff.nodes.changed == [%{id: source.id, fields: [:data]}]
      assert diff.edges.changed == [%{id: edge.id, fields: [:type, :data]}]
    end
  end

  describe "SQL ownership" do
    test "deleting a graph deletes its nodes and edges" do
      graph = insert_graph()
      source = insert_node(graph, "source")
      target = insert_node(graph, "target")
      edge = insert_edge(source, target)

      Repo.delete!(graph)

      refute Repo.get(Node, source.id)
      refute Repo.get(Node, target.id)
      refute Repo.get(Edge, edge.id)
    end

    test "deleting a node deletes incoming and outgoing edges" do
      graph = insert_graph()
      first = insert_node(graph, "first")
      middle = insert_node(graph, "middle")
      last = insert_node(graph, "last")
      incoming = insert_edge(first, middle)
      outgoing = insert_edge(middle, last)

      Repo.delete!(middle)

      refute Repo.get(Edge, incoming.id)
      refute Repo.get(Edge, outgoing.id)
    end
  end

  defp insert_graph do
    %Graph{}
    |> Graph.changeset(%{title: "test-graph"})
    |> Repo.insert!()
  end

  defp insert_node(graph, name) do
    %Node{graph_id: graph.id}
    |> Node.changeset(%{
      type: Atom.to_string(Host),
      data: %{"name" => name},
      view_data: %{"x_pos" => 0, "y_pos" => 0}
    })
    |> Repo.insert!()
  end

  defp insert_service(graph, name) do
    %Node{graph_id: graph.id}
    |> Node.changeset(%{
      type: Atom.to_string(Service),
      data: %{"name" => name, "protocol" => "tcp", "port" => 443},
      view_data: %{"x_pos" => 0, "y_pos" => 0}
    })
    |> Repo.insert!()
  end

  defp insert_edge(source, target) do
    %Edge{graph_id: source.graph_id, from_id: source.id, to_id: target.id}
    |> Edge.changeset(%{type: Atom.to_string(Runs), data: %{}})
    |> Repo.insert!()
  end

  defp node_attrs(node) do
    %{"id" => node.id, "type" => node.type, "data" => node.data, "view_data" => node.view_data}
  end

  defp edge_attrs(id, from_id, to_id, type, data \\ %{}) do
    %{
      "id" => id,
      "from_id" => from_id,
      "to_id" => to_id,
      "type" => Atom.to_string(type),
      "data" => data
    }
  end

  defp delete_all_graphs do
    Repo.delete_all(Edge)
    Repo.delete_all(Node)
    Repo.delete_all(Graph)
  end

  defp build_node(graph, type, data) do
    %Node{
      id: Ecto.UUID.generate(),
      graph_id: graph.id,
      type: Atom.to_string(type),
      data: data,
      view_data: %{"x_pos" => 0, "y_pos" => 0}
    }
  end

  defp build_edge(graph, from, to, type, data \\ %{}) do
    %Edge{
      id: Ecto.UUID.generate(),
      graph_id: graph.id,
      from_id: from.id,
      to_id: to.id,
      type: Atom.to_string(type),
      data: data
    }
  end

  defp cvss do
    %{
      "attack_vector" => "network",
      "attack_complexity" => "low",
      "privileges_required" => "none",
      "user_interaction" => "none",
      "scope" => "unchanged",
      "confidentiality_impact" => "high",
      "integrity_impact" => "none",
      "availability_impact" => "none"
    }
  end
end
