defmodule NetworkDefense.Graph.Graph do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "graphs" do
    has_many :nodes, Node
    field :adjacency_list, :map, virtual: true, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(graph, attrs) do
    graph
    |> cast(attrs, [])
    |> validate_required([])
  end

  def nodes(graph), do: loaded_nodes(graph.nodes)

  def node(graph, node_id) do
    Enum.find(nodes(graph), &(&1.id == node_id))
  end

  def outgoing(graph, node_id) do
    graph.adjacency_list
    |> Map.get(node_id, empty_adjacency())
    |> Map.fetch!(:outgoing)
  end

  def incoming(graph, node_id) do
    graph.adjacency_list
    |> Map.get(node_id, empty_adjacency())
    |> Map.fetch!(:incoming)
  end

  def load(id) do
    case Repo.get(__MODULE__, id) do
      nil -> nil
      graph -> load_adjacency_list(graph)
    end
  end

  def load!(id) do
    __MODULE__
    |> Repo.get!(id)
    |> load_adjacency_list()
  end

  def add_node(graph, node) do
    if node.graph_id != graph.id do
      raise ArgumentError, "node does not belong to graph"
    end

    if Map.has_key?(graph.adjacency_list, node.id) do
      graph
    else
      %{
        graph
        | nodes: loaded_nodes(graph.nodes) ++ [node],
          adjacency_list: Map.put(graph.adjacency_list, node.id, empty_adjacency())
      }
    end
  end

  def add_edge(graph, edge) do
    unless edge.graph_id == graph.id and Map.has_key?(graph.adjacency_list, edge.from_id) and
             Map.has_key?(graph.adjacency_list, edge.to_id) do
      raise ArgumentError, "edge endpoints must belong to graph"
    end

    adjacency_list =
      graph.adjacency_list
      |> add_outgoing_edge(edge)
      |> add_incoming_edge(edge)

    %{graph | adjacency_list: adjacency_list}
  end

  def remove_node_by_id(graph, node_id) do
    nodes =
      graph.nodes
      |> loaded_nodes()
      |> Enum.reject(&(&1.id == node_id))

    adjacency_list =
      graph.adjacency_list
      |> Map.delete(node_id)
      |> Map.new(fn {id, adjacency} ->
        {
          id,
          %{
            outgoing: Enum.reject(adjacency.outgoing, fn {to_id, _edge} -> to_id == node_id end),
            incoming:
              Enum.reject(adjacency.incoming, fn {from_id, _edge} -> from_id == node_id end)
          }
        }
      end)

    %{graph | nodes: nodes, adjacency_list: adjacency_list}
  end

  def remove_edge_by_id(graph, edge_id) do
    adjacency_list =
      Map.new(graph.adjacency_list, fn {id, adjacency} ->
        {
          id,
          %{
            outgoing:
              Enum.reject(adjacency.outgoing, fn {_to_id, edge} -> edge.id == edge_id end),
            incoming:
              Enum.reject(adjacency.incoming, fn {_from_id, edge} -> edge.id == edge_id end)
          }
        }
      end)

    %{graph | adjacency_list: adjacency_list}
  end

  defp load_adjacency_list(graph) do
    graph = Repo.preload(graph, :nodes)
    node_ids = Enum.map(graph.nodes, & &1.id)

    edges =
      Repo.all(
        from edge in Edge,
          where:
            edge.graph_id == ^graph.id and edge.from_id in ^node_ids and edge.to_id in ^node_ids,
          order_by: [asc: edge.inserted_at, asc: edge.id]
      )

    adjacency_list =
      graph.nodes
      |> Map.new(&{&1.id, empty_adjacency()})
      |> add_edges(edges)

    %{graph | adjacency_list: adjacency_list}
  end

  defp add_edges(adjacency_list, edges) do
    Enum.reduce(edges, adjacency_list, fn edge, adjacency_list ->
      adjacency_list
      |> add_outgoing_edge(edge)
      |> add_incoming_edge(edge)
    end)
  end

  defp add_outgoing_edge(adjacency_list, edge) do
    Map.update!(adjacency_list, edge.from_id, fn adjacency ->
      %{adjacency | outgoing: adjacency.outgoing ++ [{edge.to_id, edge}]}
    end)
  end

  defp add_incoming_edge(adjacency_list, edge) do
    Map.update!(adjacency_list, edge.to_id, fn adjacency ->
      %{adjacency | incoming: adjacency.incoming ++ [{edge.from_id, edge}]}
    end)
  end

  defp empty_adjacency, do: %{incoming: [], outgoing: []}

  defp loaded_nodes(nodes) when is_list(nodes), do: nodes
  defp loaded_nodes(%Ecto.Association.NotLoaded{}), do: []
end
