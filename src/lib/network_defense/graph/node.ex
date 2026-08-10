defmodule NetworkDefense.Graph.Node do
  @moduledoc """
  Represents a Node instance with type-specific data stored via (type, data) fields.

  The dynamic data is validated (forwarded) via dedicated embedded_schema types for each node type.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias NetworkDefense.Graph.Data
  alias NetworkDefense.Graph.Contracts.Node, as: NodeContract
  alias NetworkDefense.Nodes.Registry

  @primary_key false
  @foreign_key_type :binary_id
  schema "graph_revision_nodes" do
    field :id, :binary_id, source: :node_id, primary_key: true
    field :graph_revision_id, :binary_id, primary_key: true
    field :graph_id, :binary_id

    field :type, :string
    field :data, :map
    field :view_data, :map
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          graph_revision_id: Ecto.UUID.t() | nil,
          graph_id: Ecto.UUID.t() | nil,
          type: module() | String.t() | nil,
          data: map() | nil,
          view_data: map() | nil
        }

  @doc false
  def changeset(node, attrs) do
    node
    |> cast(attrs, [:type, :data, :view_data])
    |> validate_required([:type, :view_data])
    |> Data.validate_dynamic_data(Registry)
    |> validate_view_data()
  end

  def new(graph_id, attrs) do
    attrs
    |> Map.merge(%{id: Ecto.UUID.generate(), graph_id: graph_id})
    |> then(&struct!(__MODULE__, &1))
  end

  def draft(type, %{x_pos: x_pos, y_pos: y_pos})
      when is_binary(type) and is_number(x_pos) and is_number(y_pos) do
    with module when not is_nil(module) <- Registry.module_for_contract(type),
         {:ok, node} <-
           NodeContract.validate(%{
             id: Ecto.UUID.generate(),
             type: type,
             data: module.default_data(),
             view_data: %{x_pos: x_pos, y_pos: y_pos}
           }) do
      {:ok, NodeContract.to_wire(node)}
    else
      _ -> :error
    end
  end

  def draft(_type, _position), do: :error

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

  defp normalize_view_data(%{"x_pos" => x_pos, "y_pos" => y_pos} = view_data)
       when is_number(x_pos) and is_number(y_pos),
       do: {:ok, %{x_pos: x_pos, y_pos: y_pos, radius: Map.get(view_data, "radius")}}

  defp normalize_view_data(nil), do: {:ok, %{x_pos: 0, y_pos: 0, radius: nil}}
  defp normalize_view_data(_view_data), do: :error

  def view_data_params(%{x_pos: x_pos, y_pos: y_pos, radius: radius}) do
    %{"x_pos" => x_pos, "y_pos" => y_pos, "radius" => radius}
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end
end
