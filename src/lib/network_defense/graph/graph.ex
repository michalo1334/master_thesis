defmodule NetworkDefense.Graph.Graph do
  use Ecto.Schema
  import Ecto.Changeset

  alias NetworkDefense.Graph.{Edge, Folder, GraphRevision, Node}
  alias NetworkDefense.Graph.SemanticConnectivity

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "graphs" do
    belongs_to :folder, Folder
    has_many :revisions, GraphRevision
    field :adjacency_list, :map, virtual: true, default: %{}
    field :revision_id, :binary_id, virtual: true
    field :parent_revision_id, :binary_id, virtual: true
    field :revision_number, :integer, virtual: true
    field :revision_kind, Ecto.Enum, values: [:initial, :edit, :optimization], virtual: true
    field :title, :string, virtual: true
    field :nodes, {:array, :map}, virtual: true, default: []
    field :edges, {:array, :map}, virtual: true, default: []

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  @doc false
  def changeset(graph, attrs) do
    graph
    |> cast(attrs, [:title])
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 255)
  end

  def new(title) when is_binary(title) and byte_size(title) > 0 do
    %__MODULE__{
      id: Ecto.UUID.generate(),
      title: title,
      nodes: [],
      edges: [],
      adjacency_list: %{},
      revision_kind: :initial
    }
  end

  def hydrate(graph, nodes, edges) do
    graph = %{graph | nodes: [], edges: [], adjacency_list: %{}}

    case hydrate_nodes(graph, nodes) do
      {:ok, graph} -> hydrate_edges(graph, edges)
      {:error, _reason} = error -> error
    end
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

  def persisted_nodes(graph), do: Enum.map(nodes(graph), &Node.persist/1)
  def persisted_edges(graph), do: Enum.map(edges(graph), &Edge.persist/1)

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

  def add_node(graph, %Node{} = node), do: put_node(graph, Node.hydrate!(node))

  def add_node(graph, attrs) when is_map(attrs),
    do: add_node(graph, Node.new(graph.id, attrs))

  def update_node(graph, %Node{} = updated_node) do
    updated_node = Node.hydrate!(updated_node)
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

  def add_edge(graph, %Edge{} = edge) do
    case Edge.hydrate(edge) do
      {:ok, edge} -> put_edge!(graph, edge)
      :error -> raise ArgumentError, "invalid edge"
    end
  end

  def add_edge(graph, %Node{} = from, %Node{} = to, attrs) when is_map(attrs) do
    add_edge(graph, Edge.new(graph.id, from.id, to.id, attrs))
  end

  def update_edge(graph, %Edge{} = updated_edge) do
    updated_edge = Edge.hydrate!(updated_edge)
    edge!(graph, updated_edge.id)

    graph
    |> remove_edge_by_id(updated_edge.id)
    |> put_edge!(updated_edge)
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
    with true <- edge.graph_id == graph.id,
         %Node{} = from_node <- node(graph, edge.from_id),
         %Node{} = to_node <- node(graph, edge.to_id),
         true <- SemanticConnectivity.valid?(edge.type, from_node.type, to_node.type) do
      adjacency_list = graph.adjacency_list |> add_outgoing_edge(edge) |> add_incoming_edge(edge)
      {:ok, %{graph | adjacency_list: adjacency_list}}
    else
      _ -> {:error, :invalid_endpoints}
    end
  end

  defp put_edge!(graph, edge) do
    case put_edge(graph, edge) do
      {:ok, graph} ->
        graph

      {:error, :invalid_endpoints} ->
        raise ArgumentError, "edge type is not valid for graph endpoints"
    end
  end

  defp hydrate_nodes(graph, nodes) do
    Enum.reduce_while(nodes, {:ok, graph}, fn node, {:ok, graph} ->
      case Node.hydrate(node) do
        {:ok, %{graph_id: graph_id} = node} when graph_id == graph.id ->
          {:cont, {:ok, put_node(graph, node)}}

        _ ->
          {:halt, {:error, :invalid_graph}}
      end
    end)
  end

  defp hydrate_edges(graph, edges) do
    Enum.reduce_while(edges, {:ok, graph}, fn edge, {:ok, graph} ->
      with {:ok, edge} <- Edge.hydrate(edge),
           {:ok, graph} <- put_edge(graph, edge) do
        {:cont, {:ok, graph}}
      else
        _ -> {:halt, {:error, :invalid_endpoints}}
      end
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
