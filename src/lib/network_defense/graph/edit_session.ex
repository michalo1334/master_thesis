defmodule NetworkDefense.Graph.EditSession do
  @moduledoc """
  Couples graph edits with the database operations required to persist them.
  """

  alias Ecto.Changeset
  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Repo
  alias NetworkDefense.UnitOfWork

  defstruct [:graph, unit_of_work: UnitOfWork.new()]

  def new, do: from_graph(Graph.new())

  def from_graph(graph) do
    unit_of_work =
      UnitOfWork.new()
      |> UnitOfWork.insert(Graph.changeset(%{graph | nodes: [], edges: []}, %{}))
      |> add_nodes(Graph.nodes(graph))
      |> add_edges(Graph.edges(graph))

    %__MODULE__{graph: graph, unit_of_work: unit_of_work}
  end

  def load!(id), do: %__MODULE__{graph: Graphs.load!(id)}

  def add_node(session, attrs) do
    node =
      session.graph.id
      |> Node.new(%{})
      |> Node.changeset(attrs)
      |> Changeset.apply_action!(:insert)

    %{
      session
      | graph: Graph.add_node(session.graph, node),
        unit_of_work: UnitOfWork.insert(session.unit_of_work, Node.changeset(node, %{}))
    }
  end

  def update_node(session, node_id, attrs) do
    node =
      Graph.node(session.graph, node_id) || raise ArgumentError, "node does not belong to graph"

    changeset = Node.changeset(node, attrs)
    updated_node = Changeset.apply_action!(changeset, :update)

    %{
      session
      | graph: Graph.update_node(session.graph, updated_node),
        unit_of_work: UnitOfWork.update(session.unit_of_work, changeset)
    }
  end

  def add_edge(session, from, to, attrs) do
    edge =
      Edge.new(session.graph.id, from.id, to.id, %{})
      |> Edge.changeset(attrs)
      |> Changeset.apply_action!(:insert)

    %{
      session
      | graph: Graph.add_edge(session.graph, edge),
        unit_of_work: UnitOfWork.insert(session.unit_of_work, Edge.changeset(edge, %{}))
    }
  end

  def update_edge(session, edge_id, attrs) do
    edge =
      Graph.edge(session.graph, edge_id) || raise ArgumentError, "edge does not belong to graph"

    changeset = Edge.changeset(edge, attrs)
    updated_edge = Changeset.apply_action!(changeset, :update)

    %{
      session
      | graph: Graph.update_edge(session.graph, updated_edge),
        unit_of_work: UnitOfWork.update(session.unit_of_work, changeset)
    }
  end

  def remove_node(session, node_id) do
    node =
      Graph.node(session.graph, node_id) || raise ArgumentError, "node does not belong to graph"

    edges =
      Enum.filter(Graph.edges(session.graph), &(&1.from_id == node_id or &1.to_id == node_id))

    unit_of_work =
      Enum.reduce(edges, session.unit_of_work, fn edge, unit_of_work ->
        UnitOfWork.delete(unit_of_work, edge)
      end)
      |> UnitOfWork.delete(node)

    %{
      session
      | graph: Graph.remove_node_by_id(session.graph, node_id),
        unit_of_work: unit_of_work
    }
  end

  def remove_edge(session, edge_id) do
    edge =
      Graph.edge(session.graph, edge_id) || raise ArgumentError, "edge does not belong to graph"

    %{
      session
      | graph: Graph.remove_edge_by_id(session.graph, edge_id),
        unit_of_work: UnitOfWork.delete(session.unit_of_work, edge)
    }
  end

  def save(session) do
    case UnitOfWork.commit(session.unit_of_work, Repo) do
      {:ok, _changes} -> {:ok, %__MODULE__{graph: Graphs.load!(session.graph.id)}}
      error -> error
    end
  end

  defp add_nodes(unit_of_work, nodes) do
    Enum.reduce(nodes, unit_of_work, fn node, unit_of_work ->
      UnitOfWork.insert(unit_of_work, Node.changeset(node, %{}))
    end)
  end

  defp add_edges(unit_of_work, edges) do
    Enum.reduce(edges, unit_of_work, fn edge, unit_of_work ->
      UnitOfWork.insert(unit_of_work, Edge.changeset(edge, %{}))
    end)
  end
end
