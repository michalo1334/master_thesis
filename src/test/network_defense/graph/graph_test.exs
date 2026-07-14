defmodule NetworkDefense.Graph.GraphTest do
  use NetworkDefense.DataCase, async: true

  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Graph.Nodes.Host
  alias NetworkDefense.Relationships.Runs

  describe "load/1" do
    test "loads an empty graph" do
      graph = insert_graph()

      loaded_graph = Graph.load!(graph.id)

      assert loaded_graph.nodes == []
      assert loaded_graph.adjacency_list == %{}
    end

    test "loads all nodes and builds a directed adjacency list" do
      graph = insert_graph()
      source = insert_node(graph, "source")
      target = insert_node(graph, "target")
      isolated = insert_node(graph, "isolated")
      edge = insert_edge(source, target)

      loaded_graph = Graph.load(graph.id)

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
      assert Graph.load(Ecto.UUID.generate()) == nil
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
end
