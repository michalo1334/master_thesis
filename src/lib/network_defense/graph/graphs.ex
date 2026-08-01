defmodule NetworkDefense.Graph.Graphs do
  @moduledoc """
  Loads persisted graphs into their in-memory adjacency representation.
  """

  require Logger

  import Ecto.Query

  alias Ecto.Changeset
  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Contracts.GraphContract
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.GraphDiff
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Graph.SemanticConnectivity
  alias NetworkDefense.Repo

  def insert(%Graph{} = graph) do
    Repo.transaction(fn ->
      persisted_graph =
        graph
        |> Graph.insert_changeset()
        |> insert_or_rollback(:graph)

      insert_nodes(Graph.persisted_nodes(graph))
      insert_edges(Graph.persisted_edges(graph))

      hydrate_graph(persisted_graph)
    end)
  end

  def load(id) do
    Graph
    |> Repo.get(id)
    |> hydrate_graph_if_found()
  end

  def load!(id) do
    Graph
    |> Repo.get!(id)
    |> hydrate_graph()
  end

  defp hydrate_graph_if_found(nil), do: nil
  defp hydrate_graph_if_found(graph), do: hydrate_graph(graph)

  def list_summaries do
    graphs =
      Graph
      |> order_by([graph], asc: graph.title)
      |> select([graph], %{
        id: graph.id,
        title: graph.title,
        parent_id: graph.parent_id,
        tags: graph.tags
      })
      |> Repo.all()

    if graphs == [] do
      []
    else
      graph_ids = Enum.map(graphs, & &1.id)

      node_counts =
        from(n in Node,
          where: n.graph_id in ^graph_ids,
          group_by: n.graph_id,
          select: {n.graph_id, count(n.id)}
        )
        |> Repo.all()
        |> Map.new()

      edge_counts =
        from(e in Edge,
          where: e.graph_id in ^graph_ids,
          group_by: e.graph_id,
          select: {e.graph_id, count(e.id)}
        )
        |> Repo.all()
        |> Map.new()

      Enum.map(graphs, fn graph ->
        %{
          id: graph.id,
          title: graph.title,
          parentId: graph.parent_id,
          tags: Enum.map(graph.tags, &Atom.to_string/1),
          nodeCount: Map.get(node_counts, graph.id, 0),
          edgeCount: Map.get(edge_counts, graph.id, 0)
        }
      end)
    end
  end

  def replace(id, expected_lock_version, attrs)
      when is_binary(id) and is_integer(expected_lock_version) and is_map(attrs) do
    # credo:disable-for-next-line Credo.Check.Warning.MissedMetadataKeyInLoggerConfig
    Logger.debug("Graph replacement started",
      event: "graph.replace.started",
      graph: %{id: id, lock_version: expected_lock_version, attrs: attrs}
    )

    result =
      with {:ok, id} <- Ecto.UUID.cast(id),
           {:ok, candidate} <- candidate_graph(id, expected_lock_version, attrs) do
        Repo.transaction(fn -> replace_in_transaction(id, expected_lock_version, candidate) end)
      end

    # credo:disable-for-next-line Credo.Check.Warning.MissedMetadataKeyInLoggerConfig
    Logger.debug("Graph replacement completed", event: "graph.replace.completed", result: result)
    result
  end

  def replace(_id, _expected_lock_version, _attrs), do: {:error, :invalid_graph}

  def replace(%GraphContract{} = request) do
    case GraphContract.to_replace_attrs(request) do
      {:ok, %{id: id, lock_version: lock_version, attrs: attrs}} ->
        replace(id, lock_version, attrs)

      _error ->
        {:error, :invalid_graph}
    end
  end

  def build(%GraphContract{} = request) do
    with {:ok, %{id: id, lock_version: lock_version, attrs: attrs}} <-
           GraphContract.to_replace_attrs(request),
         {:ok, tags} <- graph_tags(request.tags),
         {:ok, graph} <- candidate_graph(id, lock_version, attrs) do
      {:ok, %{graph | parent_id: request.parent_id, tags: tags}}
    else
      _error -> {:error, :invalid_graph}
    end
  end

  defp hydrate_graph(%Graph{} = graph) do
    graph = Repo.preload(graph, [:nodes, :edges], force: true)
    Graph.hydrate(graph, graph.nodes, graph.edges)
  end

  defp replace_in_transaction(id, expected_lock_version, candidate) do
    graph =
      Graph
      |> where([graph], graph.id == ^id)
      |> lock("FOR UPDATE")
      |> Repo.one()

    cond do
      is_nil(graph) ->
        Repo.rollback(:not_found)

      graph.lock_version != expected_lock_version ->
        Repo.rollback(:stale)

      true ->
        persisted = hydrate_graph(graph)
        diff = GraphDiff.compare(persisted, candidate)

        if GraphDiff.empty?(diff) do
          %{graph: persisted, diff: diff}
        else
          replace_graph(persisted, candidate, diff)
        end
    end
  end

  defp replace_graph(persisted, candidate, diff) do
    updated_graph =
      persisted
      |> Graph.changeset(%{title: candidate.title})
      |> Changeset.force_change(:title, candidate.title)
      |> Changeset.optimistic_lock(:lock_version)
      |> update_or_rollback(:graph)

    Repo.delete_all(from(edge in Edge, where: edge.graph_id == ^persisted.id))
    Repo.delete_all(from(node in Node, where: node.graph_id == ^persisted.id))
    insert_nodes(Graph.persisted_nodes(candidate))
    insert_edges(Graph.persisted_edges(candidate))

    %{graph: hydrate_graph(updated_graph), diff: diff}
  end

  defp candidate_graph(
         graph_id,
         lock_version,
         %{
           "title" => title,
           "nodes" => node_attrs,
           "edges" => edge_attrs
         }
       )
       when is_binary(title) and is_list(node_attrs) and is_list(edge_attrs) do
    with {:ok, nodes} <- candidate_nodes(graph_id, node_attrs),
         :ok <- unique_ids(nodes),
         {:ok, edges} <- candidate_edges(graph_id, edge_attrs),
         :ok <- unique_ids(edges),
         :ok <- valid_endpoints(edges, nodes),
         {:ok, graph} <-
           %Graph{id: graph_id, lock_version: lock_version, nodes: [], edges: []}
           |> Graph.changeset(%{title: title})
           |> Changeset.apply_action(:update) do
      {:ok, Graph.hydrate(graph, nodes, edges)}
    else
      error ->
        # credo:disable-for-next-line Credo.Check.Warning.MissedMetadataKeyInLoggerConfig
        Logger.debug("Graph candidate invalid", event: "graph.candidate.invalid", error: error)
        {:error, :invalid_graph}
    end
  end

  defp candidate_graph(_graph_id, _lock_version, _attrs), do: {:error, :invalid_graph}

  defp candidate_nodes(graph_id, attrs) do
    map_candidates(attrs, fn
      %{"id" => id, "type" => type, "data" => data, "view_data" => view_data}
      when is_map(data) and is_map(view_data) ->
        with {:ok, id} <- Ecto.UUID.cast(id) do
          %Node{id: id, graph_id: graph_id}
          |> Node.changeset(%{type: type, data: data, view_data: view_data})
          |> Changeset.apply_action(:insert)
        end

      _attrs ->
        {:error, :invalid_node}
    end)
  end

  defp candidate_edges(graph_id, attrs) do
    map_candidates(attrs, fn
      %{
        "id" => id,
        "from_id" => from_id,
        "to_id" => to_id,
        "type" => type,
        "data" => data
      }
      when is_map(data) ->
        with {:ok, id} <- Ecto.UUID.cast(id),
             {:ok, from_id} <- Ecto.UUID.cast(from_id),
             {:ok, to_id} <- Ecto.UUID.cast(to_id) do
          %Edge{id: id, graph_id: graph_id, from_id: from_id, to_id: to_id}
          |> Edge.changeset(%{type: type, data: data})
          |> Changeset.apply_action(:insert)
        end

      _attrs ->
        {:error, :invalid_edge}
    end)
  end

  defp map_candidates(attrs, mapper) do
    Enum.reduce_while(attrs, {:ok, []}, fn attrs, {:ok, entities} ->
      case mapper.(attrs) do
        {:ok, entity} -> {:cont, {:ok, [entity | entities]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, entities} -> {:ok, Enum.reverse(entities)}
      error -> error
    end
  end

  defp unique_ids(entities) do
    if entities |> Enum.map(& &1.id) |> Enum.uniq() |> length() == length(entities),
      do: :ok,
      else: {:error, :duplicate_ids}
  end

  defp graph_tags(tags) do
    tags
    |> Enum.reduce_while({:ok, []}, fn
      "original", {:ok, values} -> {:cont, {:ok, [:original | values]}}
      "optimization", {:ok, values} -> {:cont, {:ok, [:optimization | values]}}
      _tag, _values -> {:halt, :error}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      :error -> :error
    end
  end

  defp valid_endpoints(edges, nodes) do
    node_ids = MapSet.new(nodes, & &1.id)
    nodes_by_id = Map.new(nodes, &{&1.id, &1})

    generic_ok? =
      Enum.all?(
        edges,
        &(MapSet.member?(node_ids, &1.from_id) and MapSet.member?(node_ids, &1.to_id))
      )

    case generic_ok? do
      true -> valid_semantic_endpoints(edges, nodes_by_id)
      false -> {:error, :invalid_endpoints}
    end
  end

  defp valid_semantic_endpoints(edges, nodes_by_id) do
    endpoints_valid? =
      Enum.all?(edges, fn edge ->
        from_node = Map.get(nodes_by_id, edge.from_id)
        to_node = Map.get(nodes_by_id, edge.to_id)

        with relationship_type when not is_nil(relationship_type) <-
               NetworkDefense.Relationships.Registry.module_for(edge.type),
             from_type when not is_nil(from_type) <-
               NetworkDefense.Nodes.Registry.module_for(from_node.type),
             to_type when not is_nil(to_type) <-
               NetworkDefense.Nodes.Registry.module_for(to_node.type) do
          SemanticConnectivity.valid?(relationship_type, from_type, to_type)
        else
          _ -> false
        end
      end)

    if endpoints_valid?, do: :ok, else: {:error, :invalid_graph}
  end

  defp insert_nodes(nodes),
    do: Enum.each(nodes, &insert_or_rollback(Node.changeset(&1, %{}), :node))

  defp insert_edges(edges),
    do: Enum.each(edges, &insert_or_rollback(Edge.changeset(&1, %{}), :edge))

  defp insert_or_rollback(changeset, operation) do
    case Repo.insert(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback({operation, changeset})
    end
  end

  defp update_or_rollback(changeset, operation) do
    case Repo.update(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback({operation, changeset})
    end
  end
end
