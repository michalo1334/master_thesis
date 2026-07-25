defmodule NetworkDefense.Graph.Node do
  @moduledoc """
  Represents a Node instance with type-specific data stored via (type, data) fields.

  The dynamic data is validated (forwarded) via dedicated embedded_schema types for each node type.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias NetworkDefense.Graph.{Data, Graph}
  alias NetworkDefense.Nodes.Registry

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "nodes" do
    belongs_to :graph, Graph

    field :type, :string
    field :data, :map
    field :view_data, :map

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(node, attrs) do
    node
    |> cast(attrs, [:type, :data, :view_data])
    |> validate_required([:type, :view_data])
    |> foreign_key_constraint(:graph_id)
    |> validate_dynamic_data()
    |> validate_view_data()
  end

  def new(graph_id, attrs) do
    attrs
    |> Map.merge(%{id: Ecto.UUID.generate(), graph_id: graph_id})
    |> then(&struct!(__MODULE__, &1))
  end

  def hydrate(%__MODULE__{type: type} = node) when is_atom(type), do: {:ok, node}

  def hydrate(%__MODULE__{} = node) do
    with type when not is_nil(type) <- Registry.module_for(node.type),
         {:ok, data} <- Data.load(type, node.data),
         {:ok, view_data} <- normalize_view_data(node.view_data) do
      {:ok, %{node | type: type, data: data, view_data: view_data}}
    else
      _ -> :error
    end
  end

  def hydrate!(node) do
    case hydrate(node) do
      {:ok, hydrated} -> hydrated
      :error -> raise ArgumentError, "invalid persisted node"
    end
  end

  def persist(%__MODULE__{} = node) do
    %{
      node
      | type: Registry.type_for(node.type),
        data: Data.to_params(node.data),
        view_data: view_data_params(node.view_data)
    }
  end

  def position(%__MODULE__{view_data: %{x_pos: x_pos, y_pos: y_pos}}),
    do: {x_pos, y_pos}

  def position(%__MODULE__{view_data: %{"x_pos" => x_pos, "y_pos" => y_pos}}),
    do: {x_pos, y_pos}

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

  defp validate_view_data(changeset) do
    case get_field(changeset, :view_data) do
      nil ->
        changeset

      %{"x_pos" => x_pos, "y_pos" => y_pos} when is_number(x_pos) and is_number(y_pos) ->
        changeset

      _view_data ->
        add_error(changeset, :view_data, "must contain numeric x_pos and y_pos")
    end
  end

  defp schema_for(type), do: Registry.module_for(type)

  defp normalize_view_data(%{"x_pos" => x_pos, "y_pos" => y_pos} = view_data)
       when is_number(x_pos) and is_number(y_pos),
       do: {:ok, %{x_pos: x_pos, y_pos: y_pos, radius: Map.get(view_data, "radius")}}

  defp normalize_view_data(nil), do: {:ok, %{x_pos: 0, y_pos: 0, radius: nil}}
  defp normalize_view_data(_view_data), do: :error

  defp view_data_params(%{x_pos: x_pos, y_pos: y_pos, radius: radius}) do
    %{"x_pos" => x_pos, "y_pos" => y_pos, "radius" => radius}
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end
end
