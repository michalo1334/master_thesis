defmodule NetworkDefense.Graph.Edge do
  use Ecto.Schema
  import Ecto.Changeset

  alias NetworkDefense.DynamicData
  alias NetworkDefense.Relationships.Registry, as: RelationshipRegistry

  @primary_key false
  @foreign_key_type :binary_id
  schema "graph_revision_edges" do
    field(:id, :binary_id, source: :edge_id, primary_key: true)
    field(:graph_revision_id, :binary_id, primary_key: true)
    field(:graph_id, :binary_id)
    field(:from_id, :binary_id)
    field(:to_id, :binary_id)

    field(:type, :string)
    field(:data, :map)
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          graph_revision_id: Ecto.UUID.t() | nil,
          graph_id: Ecto.UUID.t() | nil,
          from_id: Ecto.UUID.t() | nil,
          to_id: Ecto.UUID.t() | nil,
          type: module() | String.t() | nil,
          data: map() | nil
        }

  @doc false
  def changeset(edge, attrs) do
    edge
    |> cast(attrs, [:type, :data])
    |> validate_required([:type])
    |> DynamicData.validate_dynamic_data(RelationshipRegistry)
  end

  def new(graph_id, from_id, to_id, attrs) do
    attrs
    |> Map.merge(%{
      id: Ecto.UUID.generate(),
      graph_id: graph_id,
      from_id: from_id,
      to_id: to_id
    })
    |> then(&struct!(__MODULE__, &1))
  end

  def hydrate(%__MODULE__{type: type} = edge) when is_atom(type), do: {:ok, edge}

  def hydrate(%__MODULE__{} = edge) do
    with type when not is_nil(type) <- RelationshipRegistry.module_for(edge.type),
         {:ok, data} <- DynamicData.load(type, edge.data) do
      {:ok, %{edge | type: type, data: data}}
    else
      _ -> :error
    end
  end

  def hydrate!(edge) do
    case hydrate(edge) do
      {:ok, hydrated} -> hydrated
      :error -> raise ArgumentError, "invalid persisted edge"
    end
  end

  def persist(%__MODULE__{} = edge) do
    %{
      edge
      | type: RelationshipRegistry.type_for(edge.type),
        data: DynamicData.to_params(edge.data)
    }
  end
end
