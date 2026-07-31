defmodule NetworkDefense.Graph.Edge do
  use Ecto.Schema
  import Ecto.Changeset

  alias NetworkDefense.Relationships.Registry, as: RelationshipRegistry
  alias NetworkDefense.Graph.{Data, Graph, SemanticConnectivity}
  alias NetworkDefense.Graph.Contracts.Edge, as: EdgeContract
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Nodes.Registry, as: NodeRegistry

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

  def draft(relationship_type, %{id: from_id, type: from_type}, %{id: to_id, type: to_type})
      when is_binary(relationship_type) and is_binary(from_id) and is_binary(to_id) do
    with relationship when not is_nil(relationship) <-
           RelationshipRegistry.module_for_contract(relationship_type),
         from when not is_nil(from) <- NodeRegistry.module_for_contract(from_type),
         to when not is_nil(to) <- NodeRegistry.module_for_contract(to_type),
         true <- SemanticConnectivity.valid?(relationship, from, to),
         {:ok, edge} <-
           EdgeContract.validate(%{
             id: Ecto.UUID.generate(),
             from_id: from_id,
             to_id: to_id,
             type: relationship_type,
             data: relationship.default_data()
           }) do
      {:ok, EdgeContract.to_wire(edge)}
    else
      _ -> :error
    end
  end

  def draft(_relationship_type, _from, _to), do: :error

  def hydrate(%__MODULE__{type: type} = edge) when is_atom(type), do: {:ok, edge}

  def hydrate(%__MODULE__{} = edge) do
    with type when not is_nil(type) <- RelationshipRegistry.module_for(edge.type),
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
    %{edge | type: RelationshipRegistry.type_for(edge.type), data: Data.to_params(edge.data)}
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

  defp schema_for(type), do: RelationshipRegistry.module_for(type)
end
