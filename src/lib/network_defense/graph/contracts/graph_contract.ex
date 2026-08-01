defmodule NetworkDefense.Graph.Contracts.GraphContract do
  @moduledoc false

  use NetworkDefense.Contracts, category: :graph

  alias NetworkDefense.Graph.Contracts.{Edge, Node}
  alias NetworkDefense.Graph.Graph

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
