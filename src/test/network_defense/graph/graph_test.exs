defmodule NetworkDefense.Graph.GraphTest do
  use NetworkDefense.DataCase, async: true

  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.EditSession
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Nodes.Service
  alias NetworkDefense.Nodes.Vulnerability
  alias NetworkDefense.Relationships.HasVulnerability
  alias NetworkDefense.Relationships.NetworkReachability
  alias NetworkDefense.Relationships.Runs

  describe "persistence" do
    test "creates and loads a graph with typed nodes and edges" do
      graph = Graph.new()
      source_host = build_node(graph, Host, %{"name" => "internet"})
      target_host = build_node(graph, Host, %{"name" => "web-01"})

      service =
        build_node(graph, Service, %{"name" => "nginx", "protocol" => "tcp", "port" => 443})

      vulnerability =
        build_node(graph, Vulnerability, %{
          "identifier" => "CVE-2024-0001",
          "cvss_score" => 7.5,
          "exploit_probability" => 0.8
        })

      reachability_edge = build_edge(graph, source_host, service, NetworkReachability)
      runs_edge = build_edge(graph, target_host, service, Runs)
      vulnerability_edge = build_edge(graph, service, vulnerability, HasVulnerability)

      graph =
        graph
        |> Graph.add_node(source_host)
        |> Graph.add_node(target_host)
        |> Graph.add_node(service)
        |> Graph.add_node(vulnerability)
        |> Graph.add_edge(reachability_edge)
        |> Graph.add_edge(runs_edge)
        |> Graph.add_edge(vulnerability_edge)

      assert {:ok, session} = graph |> EditSession.from_graph() |> EditSession.save()
      loaded_graph = session.graph

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
      target = insert_node(graph, "target")
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
        Node.changeset(%Node{}, %{type: Atom.to_string(Host), data: %{"name" => "host"}})

      edge_changeset = Edge.changeset(%Edge{}, %{type: Atom.to_string(Runs), data: %{}})

      assert node_changeset.valid?
      assert edge_changeset.valid?
    end

    test "rejects unregistered module names" do
      changeset = Node.changeset(%Node{}, %{type: "Elixir.Unknown.Node", data: %{}})

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).type
    end
  end

  describe "in-memory updates" do
    test "builds nodes and edges with UUIDs" do
      graph = Graph.new()
      graph = Graph.add_node(graph, %{type: Atom.to_string(Host), data: %{"name" => "source"}})
      graph = Graph.add_node(graph, %{type: Atom.to_string(Host), data: %{"name" => "target"}})
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
      target = insert_node(graph, "target")
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

  describe "edit session" do
    test "persists tracked node and edge changes" do
      session =
        EditSession.new()
        |> EditSession.add_node(%{type: Atom.to_string(Host), data: %{"name" => "source"}})
        |> EditSession.add_node(%{type: Atom.to_string(Host), data: %{"name" => "target"}})

      [source, target] = session.graph.nodes

      session =
        EditSession.add_edge(session, source, target, %{type: Atom.to_string(Runs), data: %{}})

      assert {:ok, session} = EditSession.save(session)

      assert [{target_id, edge}] = Graph.outgoing(session.graph, source.id)
      assert target_id == target.id

      session =
        session
        |> EditSession.update_node(source.id, %{data: %{"name" => "renamed"}})
        |> EditSession.update_edge(edge.id, %{type: Atom.to_string(NetworkReachability)})

      assert {:ok, session} = EditSession.save(session)
      assert Graph.node(session.graph, source.id).data == %{"name" => "renamed"}

      session = EditSession.remove_node(session, target.id)
      assert {:ok, session} = EditSession.save(session)
      assert [remaining_node] = session.graph.nodes
      assert remaining_node.id == source.id
      assert Graph.outgoing(session.graph, source.id) == []
    end

    test "cancels an inserted node removed before save" do
      session =
        EditSession.new()
        |> EditSession.add_node(%{type: Atom.to_string(Host), data: %{"name" => "temporary"}})

      [node] = session.graph.nodes
      session = EditSession.remove_node(session, node.id)

      assert {:ok, session} = EditSession.save(session)
      assert session.graph.nodes == []
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
    |> Graph.changeset(%{})
    |> Repo.insert!()
  end

  defp insert_node(graph, name) do
    %Node{graph_id: graph.id}
    |> Node.changeset(%{type: Atom.to_string(Host), data: %{"name" => name}})
    |> Repo.insert!()
  end

  defp insert_edge(source, target) do
    %Edge{graph_id: source.graph_id, from_id: source.id, to_id: target.id}
    |> Edge.changeset(%{type: Atom.to_string(Runs)})
    |> Repo.insert!()
  end

  defp build_node(graph, type, data) do
    %Node{id: Ecto.UUID.generate(), graph_id: graph.id, type: Atom.to_string(type), data: data}
  end

  defp build_edge(graph, from, to, type) do
    %Edge{
      id: Ecto.UUID.generate(),
      graph_id: graph.id,
      from_id: from.id,
      to_id: to.id,
      type: Atom.to_string(type),
      data: %{}
    }
  end
end
