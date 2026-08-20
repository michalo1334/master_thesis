defmodule NetworkDefense.Graph.Graphs do
  @moduledoc """
  Persists immutable graph revisions and hydrates their adjacency representation.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias NetworkDefense.Graph.{Edge, Graph, GraphRevision, GraphRevisionFavorite, Node}
  alias NetworkDefense.Graph.Contracts.SaveGraphContract
  alias NetworkDefense.Graph.Errors, as: GraphErrors
  alias NetworkDefense.Relationships.NetworkReachability
  alias NetworkDefense.Relationships.Registry, as: RelationshipRegistry
  alias NetworkDefense.Repo
  alias NetworkDefense.Workflows

  @snapshot_insert_batch_size 1_000

  @type graph_summary :: %{
          graphId: Ecto.UUID.t(),
          folderId: Ecto.UUID.t() | nil,
          revisionId: Ecto.UUID.t(),
          parentRevisionId: Ecto.UUID.t() | nil,
          title: String.t(),
          revisionKind: String.t(),
          revisionNumber: pos_integer(),
          insertedAt: DateTime.t(),
          nodeCount: non_neg_integer(),
          edgeCount: non_neg_integer(),
          analysisIds: [Ecto.UUID.t()],
          isFavorite: boolean()
        }

  @type error :: GraphErrors.code()
  @type result(value) :: {:ok, value} | {:error, error()}
  @type append_callback(value) :: (Graph.t() -> {:ok, value} | {:error, term()})

  @spec insert(Graph.t()) :: result(Graph.t())
  def insert(%Graph{} = graph), do: create(graph)

  @spec create(Graph.t()) :: result(Graph.t())
  def create(%Graph{} = graph) do
    case candidate_graph(graph.id, graph_attrs(graph)) do
      {:ok, candidate} ->
        transaction(fn -> insert_initial_graph(candidate) end)

      {:error, _reason} = error ->
        error
    end
  end

  @spec load_revision(Ecto.UUID.t()) :: Graph.t() | {:error, GraphErrors.code()} | nil
  def load_revision(id) do
    with %GraphRevision{} = revision <- Repo.get(GraphRevision, id),
         %Graph{} = graph <- Repo.get(Graph, revision.graph_id),
         {:ok, graph} <- hydrate_revision(revision, graph) do
      graph
    end
  end

  @spec load_revision!(Ecto.UUID.t()) :: Graph.t()
  def load_revision!(id) do
    case load_revision(id) do
      nil -> raise Ecto.NoResultsError, queryable: GraphRevision
      graph -> graph
    end
  end

  @spec list_summaries() :: [graph_summary()]
  def list_summaries do
    node_counts =
      from node in Node,
        group_by: node.graph_revision_id,
        select: %{graph_revision_id: node.graph_revision_id, count: count(node.id)}

    edge_counts =
      from edge in Edge,
        group_by: edge.graph_revision_id,
        select: %{graph_revision_id: edge.graph_revision_id, count: count(edge.id)}

    analysis_ids =
      from(link in NetworkDefense.Workflows.AnalysisGraphRevision,
        group_by: link.graph_revision_id,
        select: %{
          graph_revision_id: link.graph_revision_id,
          analysis_ids: fragment("array_agg(DISTINCT ?)", link.workflow_run_id)
        }
      )

    GraphRevision
    |> join(:inner, [revision], graph in Graph, on: graph.id == revision.graph_id)
    |> join(:left, [revision], node_count in subquery(node_counts),
      on: node_count.graph_revision_id == revision.id
    )
    |> join(:left, [revision], edge_count in subquery(edge_counts),
      on: edge_count.graph_revision_id == revision.id
    )
    |> join(:left, [revision], favorite in GraphRevisionFavorite,
      on: favorite.graph_revision_id == revision.id
    )
    |> join(:left, [revision], analysis in subquery(analysis_ids),
      on: analysis.graph_revision_id == revision.id
    )
    |> order_by([revision], asc: revision.graph_id, asc: revision.number)
    |> select([revision, graph, node_count, edge_count, favorite, analysis], %{
      graphId: revision.graph_id,
      folderId: graph.folder_id,
      revisionId: revision.id,
      parentRevisionId: revision.parent_revision_id,
      title: revision.title,
      revisionKind: revision.kind,
      revisionNumber: revision.number,
      insertedAt: revision.inserted_at,
      nodeCount: coalesce(node_count.count, 0),
      edgeCount: coalesce(edge_count.count, 0),
      analysisIds:
        type(
          fragment("COALESCE(?, ARRAY[]::uuid[])", analysis.analysis_ids),
          {:array, :binary_id}
        ),
      isFavorite: not is_nil(favorite.graph_revision_id)
    })
    |> Repo.all()
    |> Enum.map(&Map.update!(&1, :revisionKind, fn kind -> Atom.to_string(kind) end))
  end

  @spec set_favorite(Ecto.UUID.t(), boolean()) :: {:ok, boolean()} | {:error, GraphErrors.code()}
  def set_favorite(id, favorite) when is_boolean(favorite) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %GraphRevision{} <- Repo.get(GraphRevision, id) do
      update_favorite(id, favorite)
    else
      :error -> {:error, :invalid_graph}
      nil -> {:error, :not_found}
    end
  end

  def set_favorite(_id, _favorite), do: {:error, :invalid_graph}

  @spec replace(Ecto.UUID.t(), map()) :: result(%{graph: Graph.t()})
  def replace(id, attrs) when is_binary(id) and is_map(attrs) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, base_revision_id} <- base_revision_id(attrs),
         {:ok, candidate} <- candidate_graph(id, attrs) do
      transaction(fn -> replace_revision(id, base_revision_id, candidate) end)
    end
  end

  def replace(_id, _attrs), do: {:error, :invalid_graph}

  @spec replace(SaveGraphContract.t()) :: result(%{graph: Graph.t()})
  def replace(%SaveGraphContract{} = request) do
    case SaveGraphContract.to_replace_attrs(request) do
      {:ok, %{id: id, base_revision_id: base_revision_id, attrs: attrs}} ->
        replace(id, Map.put(attrs, "revision_id", base_revision_id))

      _ ->
        {:error, :invalid_graph}
    end
  end

  @spec append_optimization(Graph.t()) :: result(Graph.t())
  def append_optimization(%Graph{} = graph), do: append(graph, :optimization, nil)

  @spec append_optimization(Graph.t(), append_callback(term())) ::
          result(term())
  def append_optimization(%Graph{} = graph, after_append) when is_function(after_append, 1),
    do: append(graph, :optimization, nil, after_append)

  @spec append_optimization(Graph.t(), Ecto.UUID.t(), append_callback(term())) :: result(term())
  def append_optimization(%Graph{} = graph, analysis_id, after_append)
      when (is_nil(analysis_id) or is_binary(analysis_id)) and is_function(after_append, 1),
      do: append(graph, :optimization, analysis_id, after_append)

  defp append(
         %Graph{} = graph,
         kind,
         analysis_id,
         after_append \\ fn persisted -> {:ok, persisted} end
       ) do
    with {:ok, parent_revision_id} <- base_revision_id(%{"revision_id" => graph.revision_id}),
         {:ok, candidate} <- candidate_graph(graph.id, graph_attrs(graph)) do
      transaction(fn ->
        append_and_after(graph.id, parent_revision_id, candidate, kind, analysis_id, after_append)
      end)
    end
  end

  defp append_and_after(graph_id, parent_revision_id, candidate, kind, analysis_id, after_append) do
    case append_from_graph(graph_id, parent_revision_id, candidate, kind, analysis_id) do
      {:ok, persisted} ->
        case after_append.(persisted) do
          {:ok, _value} = result -> result
          {:error, _reason} -> {:error, :internal_error}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp append_revision(graph, kind, parent_revision_id, analysis_id \\ nil) do
    number = next_revision_number(graph.id)

    revision_changeset =
      %GraphRevision{
        id: Ecto.UUID.generate(),
        graph_id: graph.id,
        parent_revision_id: parent_revision_id
      }
      |> GraphRevision.changeset(%{number: number, kind: kind, title: graph.title})

    with {:ok, revision} <- Repo.insert(revision_changeset),
         :ok <- Workflows.link_graph_revision(analysis_id, revision.id),
         :ok <- register_identities(graph),
         :ok <- insert_snapshots(graph, revision.id),
         {:ok, graph} <- hydrate_revision(revision, %Graph{id: graph.id}) do
      {:ok, graph}
    else
      {:error, %Changeset{}} -> {:error, :internal_error}
      {:error, _reason} = error -> error
    end
  end

  defp update_favorite(id, true) do
    case Repo.insert(%GraphRevisionFavorite{graph_revision_id: id},
           on_conflict: :nothing,
           conflict_target: :graph_revision_id
         ) do
      {:ok, _favorite} -> {:ok, true}
      {:error, _changeset} -> {:error, :internal_error}
    end
  end

  defp update_favorite(id, false) do
    GraphRevisionFavorite
    |> where([favorite], favorite.graph_revision_id == ^id)
    |> Repo.delete_all()

    {:ok, false}
  end

  defp insert_initial_graph(graph) do
    %Graph{id: graph.id}
    |> Changeset.change()
    |> Changeset.unique_constraint(:id, name: :graphs_pkey)
    |> Repo.insert()
    |> case do
      {:ok, _graph} -> append_revision(graph, :initial, nil)
      {:error, _changeset} -> {:error, :internal_error}
    end
  end

  defp replace_revision(id, base_revision_id, candidate) do
    case lock_graph(id) do
      nil -> {:error, :not_found}
      graph -> append_edit_revision(graph, base_revision_id, candidate)
    end
  end

  defp append_edit_revision(graph, base_revision_id, candidate) do
    case revision_for_graph(graph.id, base_revision_id) do
      nil ->
        {:error, :invalid_base_revision}

      parent ->
        case append_revision(candidate, :edit, parent.id) do
          {:ok, saved} -> {:ok, %{graph: saved}}
          {:error, _reason} = error -> error
        end
    end
  end

  defp append_from_graph(graph_id, parent_revision_id, candidate, kind, analysis_id) do
    lock_graph(graph_id)
    |> append_from_locked_graph(parent_revision_id, candidate, kind, analysis_id)
  end

  defp append_from_locked_graph(nil, _parent_revision_id, _candidate, _kind, _analysis_id),
    do: {:error, :not_found}

  defp append_from_locked_graph(graph, parent_revision_id, candidate, kind, analysis_id) do
    case revision_for_graph(graph.id, parent_revision_id) do
      nil -> {:error, :invalid_base_revision}
      parent -> append_revision(candidate, kind, parent.id, analysis_id)
    end
  end

  defp revision_for_graph(graph_id, revision_id) do
    GraphRevision
    |> where([revision], revision.id == ^revision_id and revision.graph_id == ^graph_id)
    |> Repo.one()
  end

  defp lock_graph(id) do
    Graph
    |> where([graph], graph.id == ^id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp next_revision_number(graph_id) do
    GraphRevision
    |> where([revision], revision.graph_id == ^graph_id)
    |> select([revision], coalesce(max(revision.number), 0))
    |> Repo.one()
    |> Kernel.+(1)
  end

  defp hydrate_revision(revision, graph) do
    nodes =
      Node
      |> where([node], node.graph_revision_id == ^revision.id)
      |> order_by([node], asc: node.id)
      |> Repo.all()

    edges =
      Edge
      |> where([edge], edge.graph_revision_id == ^revision.id)
      |> order_by([edge], asc: edge.id)
      |> Repo.all()

    graph
    |> Map.merge(%{
      title: revision.title,
      revision_id: revision.id,
      parent_revision_id: revision.parent_revision_id,
      revision_number: revision.number,
      revision_kind: revision.kind
    })
    |> Graph.hydrate(nodes, edges)
  end

  defp candidate_graph(
         graph_id,
         %{"title" => title, "nodes" => node_attrs, "edges" => edge_attrs}
       )
       when is_binary(title) and is_list(node_attrs) and is_list(edge_attrs) do
    with {:ok, nodes} <- candidate_nodes(graph_id, node_attrs),
         :ok <- unique_ids(nodes),
         {:ok, edges} <- candidate_edges(graph_id, edge_attrs),
         :ok <- unique_ids(edges),
         {:ok, graph} <-
           %Graph{id: graph_id, nodes: [], edges: []}
           |> Graph.changeset(%{title: title})
           |> Changeset.apply_action(:update) do
      Graph.hydrate(graph, nodes, edges)
    else
      {:error, %Changeset{}} -> {:error, :invalid_graph}
      {:error, _reason} = error -> error
      :error -> {:error, :invalid_graph}
    end
  end

  defp candidate_graph(_graph_id, _attrs), do: {:error, :invalid_graph}

  defp base_revision_id(%{"revision_id" => revision_id}) do
    case Ecto.UUID.cast(revision_id) do
      {:ok, revision_id} -> {:ok, revision_id}
      :error -> {:error, :invalid_base_revision}
    end
  end

  defp base_revision_id(_attrs), do: {:error, :invalid_base_revision}

  defp graph_attrs(graph) do
    %{
      "title" => graph.title,
      "nodes" => Graph.nodes(graph) |> Enum.map(&node_attrs/1),
      "edges" => Graph.edges(graph) |> Enum.map(&edge_attrs/1)
    }
  end

  defp node_attrs(node) do
    node
    |> Node.persist()
    |> Map.take([:id, :type, :data, :view_data])
  end

  defp edge_attrs(edge) do
    %{
      id: edge.id,
      from_id: edge.from_id,
      to_id: edge.to_id,
      type: if(is_atom(edge.type), do: Atom.to_string(edge.type), else: edge.type),
      data: NetworkDefense.Graph.Data.to_params(edge.data)
    }
  end

  defp candidate_nodes(graph_id, attrs) do
    map_candidates(attrs, fn
      %{id: id, type: type, data: data, view_data: view_data}
      when is_map(data) and is_map(view_data) ->
        make_node(graph_id, id, type, data, view_data)

      %{"id" => id, "type" => type, "data" => data, "view_data" => view_data}
      when is_map(data) and is_map(view_data) ->
        make_node(graph_id, id, type, data, view_data)

      _ ->
        {:error, :invalid_node}
    end)
  end

  defp make_node(graph_id, id, type, data, view_data) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        %Node{id: id, graph_id: graph_id}
        |> Node.changeset(%{type: type, data: data, view_data: view_data})
        |> Changeset.apply_action(:insert)
        |> case do
          {:ok, node} -> {:ok, node}
          {:error, _changeset} -> {:error, :invalid_node}
        end

      :error ->
        {:error, :invalid_node}
    end
  end

  defp candidate_edges(graph_id, attrs) do
    map_candidates(attrs, fn
      %{id: id, from_id: from_id, to_id: to_id, type: type, data: data} when is_map(data) ->
        make_edge(graph_id, id, from_id, to_id, type, data)

      %{"id" => id, "from_id" => from_id, "to_id" => to_id, "type" => type, "data" => data}
      when is_map(data) ->
        make_edge(graph_id, id, from_id, to_id, type, data)

      _ ->
        {:error, :invalid_edge}
    end)
  end

  defp make_edge(graph_id, id, from_id, to_id, type, data) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, from_id} <- Ecto.UUID.cast(from_id),
         {:ok, to_id} <- Ecto.UUID.cast(to_id),
         :ok <- reject_operational_reachability(type) do
      %Edge{id: id, graph_id: graph_id, from_id: from_id, to_id: to_id}
      |> Edge.changeset(%{type: type, data: data})
      |> Changeset.apply_action(:insert)
      |> case do
        {:ok, edge} -> {:ok, edge}
        {:error, _changeset} -> {:error, :invalid_edge}
      end
    else
      :error -> {:error, :invalid_edge}
    end
  end

  defp reject_operational_reachability(type) do
    if RelationshipRegistry.module_for(type) == NetworkReachability, do: :error, else: :ok
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

  defp register_identities(graph) do
    with :ok <- register_identities(:nodes, graph.id, Graph.nodes(graph)) do
      register_identities(:edges, graph.id, Graph.edges(graph))
    end
  end

  defp register_identities(_table, _graph_id, []), do: :ok

  defp register_identities(table, graph_id, entities) do
    ids = Enum.map(entities, & &1.id)
    database_ids = Enum.map(ids, &Ecto.UUID.dump!/1)

    now = DateTime.truncate(DateTime.utc_now(), :second)

    database_graph_id = Ecto.UUID.dump!(graph_id)

    Repo.insert_all(
      identity_table(table),
      Enum.map(
        database_ids,
        &%{id: &1, graph_id: database_graph_id, inserted_at: now, updated_at: now}
      ),
      on_conflict: :nothing
    )

    owners = identity_owners(table, database_ids)

    if length(owners) == length(database_ids) and
         Enum.all?(owners, fn {_id, owner_id} -> owner_id == database_graph_id end),
       do: :ok,
       else: {:error, :identity_belongs_to_another_graph}
  end

  defp identity_table(:nodes), do: "nodes"
  defp identity_table(:edges), do: "edges"

  defp identity_owners(:nodes, ids),
    do:
      Repo.all(
        from(entity in "nodes", where: entity.id in ^ids, select: {entity.id, entity.graph_id})
      )

  defp identity_owners(:edges, ids),
    do:
      Repo.all(
        from(entity in "edges", where: entity.id in ^ids, select: {entity.id, entity.graph_id})
      )

  defp insert_snapshots(graph, revision_id) do
    nodes =
      Enum.map(Graph.persisted_nodes(graph), fn node ->
        node
        |> Map.take([:id, :graph_id, :type, :data, :view_data])
        |> Map.put(:graph_revision_id, revision_id)
      end)

    edges =
      Enum.map(Graph.persisted_edges(graph), fn edge ->
        edge
        |> Map.take([:id, :graph_id, :from_id, :to_id, :type, :data])
        |> Map.put(:graph_revision_id, revision_id)
      end)

    insert_snapshot_rows(Node, nodes)
    insert_snapshot_rows(Edge, edges)
    :ok
  end

  defp insert_snapshot_rows(_schema, []), do: :ok

  defp insert_snapshot_rows(schema, rows) do
    rows
    |> Enum.chunk_every(@snapshot_insert_batch_size)
    |> Enum.each(&Repo.insert_all(schema, &1))
  end

  defp transaction(fun) do
    Repo.transaction(fn -> fun.() |> rollback_error() end)
    |> transaction_result()
  end

  defp rollback_error({:ok, _value} = result), do: result
  defp rollback_error({:error, reason}), do: Repo.rollback(reason)

  defp transaction_result(result) do
    case result do
      {:ok, {:ok, value}} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end
end
