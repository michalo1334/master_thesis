defmodule NetworkDefense.Graph.Contracts.SaveGraphContract do
  @moduledoc false

  use NetworkDefense.Contracts, category: :graph

  alias NetworkDefense.Graph.Contracts.{Edge, Node}

  embedded_schema do
    field :id, :string
    field :revision_id, :string
    field :title, :string
    embeds_many :nodes, Node, on_replace: :delete
    embeds_many :edges, Edge, on_replace: :delete
  end

  @type t :: %__MODULE__{
          id: String.t(),
          revision_id: String.t(),
          title: String.t(),
          nodes: [Node.t()],
          edges: [Edge.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :revision_id, :title])
    |> cast_embed(:nodes)
    |> cast_embed(:edges)
    |> validate_required([:id, :revision_id, :title])
    |> Contracts.validate_uuid(:id)
    |> Contracts.validate_uuid(:revision_id)
    |> validate_length(:title, min: 1)
  end

  def to_replace_attrs(%__MODULE__{} = graph) do
    with {:ok, nodes} <- map_contracts(graph.nodes, &Node.to_attrs/1),
         {:ok, edges} <- map_contracts(graph.edges, &Edge.to_attrs/1) do
      {:ok,
       %{
         id: graph.id,
         base_revision_id: graph.revision_id,
         attrs: %{"title" => graph.title, "nodes" => nodes, "edges" => edges}
       }}
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
