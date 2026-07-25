defmodule NetworkDefense.Graph.Edge do
  use Ecto.Schema
  import Ecto.Changeset

  alias NetworkDefense.Relationships.Registry
  alias NetworkDefense.Graph.{Data, Graph}
  alias NetworkDefense.Graph.Node

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "edges" do
    belongs_to :graph, Graph
    belongs_to :from, Node
    belongs_to :to, Node

    field :type, :string
    field :data, :map

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(edge, attrs) do
    edge
    |> cast(attrs, [:type, :data])
    |> validate_required([:type])
    |> foreign_key_constraint(:graph_id)
    |> foreign_key_constraint(:from_id, name: :edges_from_graph_fkey)
    |> foreign_key_constraint(:to_id, name: :edges_to_graph_fkey)
    |> validate_dynamic_data()
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
    with type when not is_nil(type) <- Registry.module_for(edge.type),
         {:ok, data} <- Data.load(type, edge.data) do
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
    %{edge | type: Registry.type_for(edge.type), data: Data.to_params(edge.data)}
  end

  defp validate_dynamic_data(changeset) do
    type = get_field(changeset, :type)
    data = get_field(changeset, :data)

    case schema_for(type) do
      nil ->
        add_error(changeset, :type, "is invalid")

      schema ->
        data_changeset = schema.changeset(struct(schema), data || %{})

        if data_changeset.valid? do
          changeset
        else
          add_error(changeset, :data, "is invalid")
        end
    end
  end

  defp schema_for(type), do: Registry.module_for(type)
end
