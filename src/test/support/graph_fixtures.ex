defmodule NetworkDefense.GraphFixtures do
  @moduledoc false

  alias NetworkDefense.Graph.{Edge, Graph, Node}
  alias NetworkDefense.Nodes.Credential
  alias NetworkDefense.Nodes.Registry, as: NodeRegistry
  alias NetworkDefense.Relationships.Registry, as: RelationshipRegistry

  def graph(nodes, edges, graph_id \\ "graph") do
    graph = %Graph{id: graph_id, nodes: [], adjacency_list: %{}}
    graph = Enum.reduce(nodes, graph, &Graph.add_node(&2, &1))
    Enum.reduce(edges, graph, &Graph.add_edge(&2, &1))
  end

  def node(id, type, data, graph_id \\ "graph") do
    %Node{id: id, graph_id: graph_id, type: NodeRegistry.type_for(type), data: data}
  end

  def build_node(graph, type, data) do
    %Node{
      id: Ecto.UUID.generate(),
      graph_id: graph.id,
      type: NodeRegistry.type_for(type),
      data: data,
      view_data: %{"x_pos" => 0, "y_pos" => 0}
    }
  end

  def persisted_credential_graph(graph_id \\ "graph") do
    graph = Graph.new(graph_id)

    graph
    |> build_node(Credential, %{"identifier" => "admin", "credential_type" => "password"})
    |> then(&Graph.add_node(graph, &1))
  end

  def edge(id, from, to, type, data \\ %{}) do
    %Edge{
      id: id,
      graph_id: from.graph_id,
      from_id: from.id,
      to_id: to.id,
      type: RelationshipRegistry.type_for(type),
      data: data
    }
  end
end
