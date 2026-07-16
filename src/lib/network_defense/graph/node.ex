defmodule NetworkDefense.Graph.Node do
  @moduledoc """
  Represents a Node instance with type-specific data stored via (type, data) fields.

  The dynamic data is validated (forwarded) via dedicated embedded_schema types for each node type.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Nodes.Registry

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "nodes" do
    belongs_to :graph, Graph

    field :type, :string
    field :data, :map

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(node, attrs) do
    node
    |> cast(attrs, [:type, :data])
    |> validate_required([:type])
    |> foreign_key_constraint(:graph_id)
    |> validate_dynamic_data()
  end

  def new(graph_id, attrs) do
    attrs
    |> Map.merge(%{id: Ecto.UUID.generate(), graph_id: graph_id})
    |> then(&struct!(__MODULE__, &1))
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
