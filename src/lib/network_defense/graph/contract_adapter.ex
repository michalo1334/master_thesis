defmodule NetworkDefense.Graph.ContractAdapter do
  @moduledoc false

  import Ecto.Changeset, only: [add_error: 3, change: 1]

  alias NetworkDefense.Errors
  alias NetworkDefense.Graph.Contracts.{Edge, GraphContract, Mapper, Node}
  alias NetworkDefense.Graph.Edge, as: DomainEdge
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Node, as: DomainNode

  @spec from_domain(Graph.t()) :: {:ok, map()} | {:error, term()}
  def from_domain(graph) do
    with {:ok, nodes} <- graph |> Graph.nodes() |> Mapper.map(&Node.from_domain/1),
         {:ok, edges} <- graph |> Graph.edges() |> Mapper.map(&Edge.from_domain/1),
         {:ok, contract} <-
           GraphContract.validate(%{
             id: graph.id,
             title: graph.title,
             revision_id: graph.revision_id,
             parent_revision_id: graph.parent_revision_id,
             revision_number: graph.revision_number,
             revision_kind: graph.revision_kind && Atom.to_string(graph.revision_kind),
             nodes: Enum.map(nodes, &Node.to_wire/1),
             edges: Enum.map(edges, &Edge.to_wire/1)
           }) do
      {:ok, GraphContract.to_wire(contract)}
    end
  end

  @spec to_domain(GraphContract.t(), keyword()) ::
          {:ok, Graph.t()} | {:error, Ecto.Changeset.t()}
  def to_domain(%GraphContract{} = contract, opts \\ []) do
    validate_membership = Keyword.get(opts, :validate_membership, true)

    with :ok <- structural_errors(contract),
         {:ok, nodes} <- domain_nodes(contract),
         {:ok, edges} <- domain_edges(contract),
         {:ok, graph} <- hydrate_graph(contract, nodes, edges, validate_membership) do
      {:ok, graph}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}

      {:error, {field, code}} ->
        {:error, field_error(field, code)}
    end
  end

  defp structural_errors(contract) do
    changeset =
      %GraphContract{}
      |> change()
      |> add_identity_error(contract.id, :id)
      |> add_identity_error(contract.title, :title)
      |> add_entities_error(contract.nodes, :nodes, Node)
      |> add_entities_error(contract.edges, :edges, Edge)

    if changeset.valid?, do: :ok, else: {:error, changeset}
  end

  defp add_identity_error(changeset, nil, :id), do: add_error(changeset, :id, "can't be blank")

  defp add_identity_error(changeset, nil, :title),
    do: add_error(changeset, :title, "can't be blank")

  defp add_identity_error(changeset, id, :id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _uuid} -> changeset
      _ -> add_error(changeset, :id, "is invalid")
    end
  end

  defp add_identity_error(changeset, _id, :id), do: add_error(changeset, :id, "is invalid")

  defp add_identity_error(changeset, title, :title)
       when is_binary(title) and byte_size(title) > 0,
       do: changeset

  defp add_identity_error(changeset, _title, :title),
    do: add_error(changeset, :title, "is invalid")

  defp add_entities_error(changeset, nil, field, _entity_module),
    do: add_error(changeset, field, "can't be blank")

  defp add_entities_error(changeset, entities, field, entity_module) when is_list(entities) do
    if Enum.all?(entities, &is_struct(&1, entity_module)),
      do: changeset,
      else: add_error(changeset, field, "is invalid")
  end

  defp add_entities_error(changeset, _entities, field, _entity_module),
    do: add_error(changeset, field, "is invalid")

  defp domain_nodes(contract) do
    with {:ok, attrs} <- Mapper.map(contract.nodes, &Node.to_attrs/1),
         nodes = Enum.map(attrs, &node_struct(&1, contract.id)),
         :ok <- unique_ids(nodes) do
      {:ok, nodes}
    else
      {:error, :duplicate_ids} -> {:error, {:nodes, :duplicate_ids}}
      _ -> {:error, {:nodes, :invalid_node}}
    end
  end

  defp domain_edges(contract) do
    with {:ok, attrs} <- Mapper.map(contract.edges, &Edge.to_attrs/1),
         edges = Enum.map(attrs, &edge_struct(&1, contract.id)),
         :ok <- unique_ids(edges) do
      {:ok, edges}
    else
      {:error, :duplicate_ids} -> {:error, {:edges, :duplicate_ids}}
      _ -> {:error, {:edges, :invalid_edge}}
    end
  end

  defp unique_ids(entities) do
    ids = Enum.map(entities, & &1.id)

    cond do
      Enum.any?(ids, &is_nil/1) -> :error
      length(Enum.uniq(ids)) != length(ids) -> {:error, :duplicate_ids}
      true -> :ok
    end
  end

  defp hydrate_graph(contract, nodes, edges, validate_membership) do
    case Graph.hydrate(
           %Graph{id: contract.id, title: contract.title},
           nodes,
           edges,
           validate_membership
         ) do
      {:ok, graph} -> {:ok, graph}
      {:error, reason} -> {:error, hydrate_error(reason)}
    end
  end

  defp hydrate_error(:invalid_graph), do: {:nodes, :invalid_node}
  defp hydrate_error(:invalid_endpoints), do: {:edges, :invalid_endpoints}
  defp hydrate_error(:multiple_segments), do: {:edges, :multiple_segments}
  defp hydrate_error(:multiple_runs), do: {:edges, :multiple_runs}

  defp hydrate_error(:invalid_required_flow_reference),
    do: {:nodes, :invalid_required_flow_reference}

  defp hydrate_error(:invalid_mission_capability_support),
    do: {:edges, :invalid_mission_capability_support}

  defp hydrate_error(_reason), do: {:graph, :invalid_graph}

  defp field_error(field, code) do
    %GraphContract{}
    |> change()
    |> add_error(field, Errors.to_wire(code))
  end

  defp node_struct(attrs, graph_id) do
    %DomainNode{
      id: attrs["id"],
      graph_id: graph_id,
      type: attrs["type"],
      data: attrs["data"],
      view_data: attrs["view_data"]
    }
  end

  defp edge_struct(attrs, graph_id) do
    %DomainEdge{
      id: attrs["id"],
      graph_id: graph_id,
      from_id: attrs["from_id"],
      to_id: attrs["to_id"],
      type: attrs["type"],
      data: attrs["data"]
    }
  end
end
