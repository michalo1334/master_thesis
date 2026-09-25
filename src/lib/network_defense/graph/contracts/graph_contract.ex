defmodule NetworkDefense.Graph.Contracts.GraphContract do
  @moduledoc false

  use NetworkDefense.Contracts, category: :graph

  alias NetworkDefense.Errors
  alias NetworkDefense.Graph.Contracts.{Edge, Node}
  alias NetworkDefense.Graph.Edge, as: DomainEdge
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Node, as: DomainNode

  embedded_schema do
    field :id, :string
    field :title, :string
    field :revision_id, :string
    field :parent_revision_id, :string
    field :revision_number, :integer
    field :revision_kind, :string
    embeds_many :nodes, Node, on_replace: :delete
    embeds_many :edges, Edge, on_replace: :delete
  end

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          nodes: [Node.t()],
          edges: [Edge.t()],
          revision_id: String.t() | nil,
          parent_revision_id: String.t() | nil,
          revision_number: integer() | nil,
          revision_kind: String.t() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :id,
      :title,
      :revision_id,
      :parent_revision_id,
      :revision_number,
      :revision_kind
    ])
    |> cast_embed(:nodes)
    |> cast_embed(:edges)
    |> validate_required([:id, :title])
    |> Contracts.validate_uuid(:id)
    |> Contracts.validate_uuid(:revision_id)
    |> Contracts.validate_uuid(:parent_revision_id)
    |> validate_length(:title, min: 1)
  end

  def from_domain(graph) do
    with {:ok, nodes} <- graph |> Graph.nodes() |> map_contracts(&Node.from_domain/1),
         {:ok, edges} <- graph |> Graph.edges() |> map_contracts(&Edge.from_domain/1),
         # Revalidate the assembled graph to keep outbound data within the contract.
         {:ok, contract} <-
           validate(%{
             id: graph.id,
             title: graph.title,
             revision_id: graph.revision_id,
             parent_revision_id: graph.parent_revision_id,
             revision_number: graph.revision_number,
             revision_kind: graph.revision_kind && Atom.to_string(graph.revision_kind),
             nodes: Enum.map(nodes, &Node.to_wire/1),
             edges: Enum.map(edges, &Edge.to_wire/1)
           }) do
      {:ok, contract |> to_wire()}
    end
  end

  @doc ~S|
  Converts a validated graph contract into a domain graph without persisting it.

  Node and edge conversion keeps contract validation: unknown node or
  relationship types, invalid node data, missing or type-incompatible edge
  endpoints, dangling edges, and duplicate node or edge IDs all fail the
  conversion before `Graph.hydrate/4`.

  With `validate_membership: false` the conversion also accepts incomplete or
  ambiguous semantic ownership (a host without a segment, a service run by
  two hosts). Draft projections use that mode to surface typed placement
  issues instead of errors. Malformed edges still fail it.

  Failures return an error changeset. The field names the failing part of
  the contract (`:id`, `:title`, `:nodes`, or `:edges`) and the message is a
  static cause: a `NetworkDefense.Errors` code string for malformed or
  invalid structure, or an Ecto required-value message for a contract that
  is missing its graph identity or node and edge lists.
  |
  @spec to_domain(t(), keyword()) :: {:ok, Graph.t()} | {:error, Ecto.Changeset.t()}
  def to_domain(%__MODULE__{} = contract, opts \\ []) do
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

  # Rejects structurally incomplete contracts: missing graph identity and
  # node or edge lists that are nil or not lists of node and edge contracts.
  defp structural_errors(contract) do
    changeset =
      %__MODULE__{}
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
    with {:ok, attrs} <- map_contracts(contract.nodes, &Node.to_attrs/1),
         nodes = Enum.map(attrs, &node_struct(&1, contract.id)),
         :ok <- unique_ids(nodes) do
      {:ok, nodes}
    else
      {:error, :duplicate_ids} -> {:error, {:nodes, :duplicate_ids}}
      _ -> {:error, {:nodes, :invalid_node}}
    end
  end

  defp domain_edges(contract) do
    with {:ok, attrs} <- map_contracts(contract.edges, &Edge.to_attrs/1),
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

  # Maps Graph.hydrate/4 error reasons to the contract field being repaired and
  # a stable external error code.
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
    %__MODULE__{}
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

  defp map_contracts(values, mapper) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, mapped} ->
      case mapper.(value) do
        {:ok, contract} -> {:cont, {:ok, [contract | mapped]}}
        :error -> {:halt, :error}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, mapped} -> {:ok, Enum.reverse(mapped)}
      error -> error
    end
  end
end
