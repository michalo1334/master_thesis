defmodule NetworkDefense.Graph.Graph do
  use Ecto.Schema
  import Ecto.Changeset

  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Node

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "graphs" do
    has_many :nodes, Node
    has_many :edges, Edge
    field :adjacency_list, :map, virtual: true, default: %{}
    field :title, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(graph, attrs) do
    graph
    |> cast(attrs, [:title])
    |> validate_required([:title])
    |> validate_length(:title, min: 1)
  end

  def new(title) when is_binary(title) and byte_size(title) > 0 do
    %__MODULE__{id: Ecto.UUID.generate(), title: title, nodes: [], edges: [], adjacency_list: %{}}
  end

  def hydrate(graph, nodes, edges) do
    graph = %{graph | nodes: [], edges: [], adjacency_list: %{}}
    graph = Enum.reduce(nodes, graph, &put_node(&2, &1))
    Enum.reduce(edges, graph, &put_edge(&2, &1))
  end

  def nodes(graph), do: loaded_nodes(graph.nodes)

  def edges(graph) do
    graph.adjacency_list
    |> Map.values()
    |> Enum.flat_map(& &1.outgoing)
    |> Enum.map(&elem(&1, 1))
    |> Enum.uniq_by(& &1.id)
  end

  def node(graph, node_id), do: Enum.find(nodes(graph), &(&1.id == node_id))
  def edge(graph, edge_id), do: Enum.find(edges(graph), &(&1.id == edge_id))

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

  def add_node(graph, %Node{} = node), do: put_node(graph, node)
  def add_node(graph, attrs) when is_map(attrs), do: add_node(graph, Node.new(graph.id, attrs))

  def update_node(graph, %Node{} = updated_node) do
    node!(graph, updated_node.id)

    if updated_node.graph_id != graph.id do
      raise ArgumentError, "node does not belong to graph"
    end

    %{
      graph
      | nodes:
          Enum.map(nodes(graph), fn node ->
            if node.id == updated_node.id, do: updated_node, else: node
          end)
    }
  end

  def add_edge(graph, %Edge{} = edge), do: put_edge(graph, edge)

  def add_edge(graph, %Node{} = from, %Node{} = to, attrs) when is_map(attrs) do
    add_edge(graph, Edge.new(graph.id, from.id, to.id, attrs))
  end

  def update_edge(graph, %Edge{} = updated_edge) do
    edge!(graph, updated_edge.id)

    adjacency_list =
      Map.new(graph.adjacency_list, fn {node_id, adjacency} ->
        {
          node_id,
          %{
            outgoing: replace_edge(adjacency.outgoing, updated_edge),
            incoming: replace_edge(adjacency.incoming, updated_edge)
          }
        }
      end)

    %{graph | adjacency_list: adjacency_list}
  end

  def remove_node_by_id(graph, node_id) do
    nodes = Enum.reject(nodes(graph), &(&1.id == node_id))

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

  defp put_node(graph, node) do
    if node.graph_id != graph.id, do: raise(ArgumentError, "node does not belong to graph")

    if Map.has_key?(graph.adjacency_list, node.id) do
      graph
    else
      %{
        graph
        | nodes: nodes(graph) ++ [node],
          adjacency_list: Map.put(graph.adjacency_list, node.id, empty_adjacency())
      }
    end
  end

  defp put_edge(graph, edge) do
    unless edge.graph_id == graph.id and Map.has_key?(graph.adjacency_list, edge.from_id) and
             Map.has_key?(graph.adjacency_list, edge.to_id) do
      raise ArgumentError, "edge endpoints must belong to graph"
    end

    adjacency_list = graph.adjacency_list |> add_outgoing_edge(edge) |> add_incoming_edge(edge)
    %{graph | adjacency_list: adjacency_list}
  end

  defp replace_edge(edges, updated_edge) do
    Enum.map(edges, fn {node_id, edge} ->
      if edge.id == updated_edge.id, do: {node_id, updated_edge}, else: {node_id, edge}
    end)
  end

  defp node!(graph, node_id),
    do: node(graph, node_id) || raise(ArgumentError, "node does not belong to graph")

  defp edge!(graph, edge_id),
    do: edge(graph, edge_id) || raise(ArgumentError, "edge does not belong to graph")

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
