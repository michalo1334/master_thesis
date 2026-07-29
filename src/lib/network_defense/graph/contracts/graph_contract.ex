defmodule NetworkDefense.Graph.Contracts.GraphContract do
  @moduledoc false

  use NetworkDefense.Contracts, category: :graph

  alias NetworkDefense.Graph.Contracts.{Edge, Node}
  alias NetworkDefense.Graph.Graph

  embedded_schema do
    field :id, :string
    field :title, :string
    field :lock_version, :integer
    field :parent_id, :string
    field :tags, {:array, :string}, default: []
    embeds_many :nodes, Node, on_replace: :delete
    embeds_many :edges, Edge, on_replace: :delete
  end

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          nodes: [Node.t()],
          edges: [Edge.t()],
          lock_version: integer(),
          parent_id: String.t() | nil,
          tags: [String.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :title, :lock_version, :parent_id, :tags])
    |> cast_embed(:nodes)
    |> cast_embed(:edges)
    |> validate_required([:id, :title, :lock_version])
    |> Contracts.validate_uuid(:id)
    |> Contracts.validate_uuid(:parent_id)
    |> validate_length(:title, min: 1)
  end

  def from_params(params) do
    with {:ok, graph} <- validate(params) do
      to_replace_attrs(graph)
    end
  end

  def to_replace_attrs(%__MODULE__{} = graph) do
    with {:ok, nodes} <- map_contracts(graph.nodes, &Node.to_attrs/1),
         {:ok, edges} <- map_contracts(graph.edges, &Edge.to_attrs/1) do
      {:ok,
       %{
         id: graph.id,
         lock_version: graph.lock_version,
         attrs: %{"title" => graph.title, "nodes" => nodes, "edges" => edges}
       }}
    end
  end

  def from_domain(graph) do
    with {:ok, nodes} <- graph |> Graph.nodes() |> map_contracts(&Node.from_domain/1),
         {:ok, edges} <- graph |> Graph.edges() |> map_contracts(&Edge.from_domain/1),
         # Revalidate the assembled graph to keep outbound data within the contract.
         {:ok, contract} <-
           validate(%{
             id: graph.id,
             title: graph.title,
             lock_version: graph.lock_version,
             nodes: Enum.map(nodes, &Node.to_wire/1),
             edges: Enum.map(edges, &Edge.to_wire/1)
           }) do
      {:ok,
       contract
       |> Map.put(:parent_id, graph.parent_id)
       |> Map.put(:tags, Enum.map(graph.tags, &Atom.to_string/1))
       |> to_wire()}
    end
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
