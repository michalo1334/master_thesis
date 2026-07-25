defmodule NetworkDefense.Graph.Domain.Adapter do
  @moduledoc false

  alias Ecto.Changeset
  alias NetworkDefense.Graph.Domain.ViewData
  alias NetworkDefense.Nodes.Registry, as: NodeRegistry
  alias NetworkDefense.Relationships.Registry, as: RelationshipRegistry

  def hydrate_node(%NetworkDefense.Graph.Node{} = node) do
    with type when not is_nil(type) <- NodeRegistry.module_for(node.type),
         {:ok, data} <- load_data(type, node.data),
         {:ok, view_data} <- ViewData.from_params(node.view_data) do
      {:ok,
       %NetworkDefense.Graph.Domain.Node{
         id: node.id,
         graph_id: node.graph_id,
         type: type,
         data: data,
         view_data: view_data
       }}
    else
      _ -> :error
    end
  end

  def hydrate_node!(node) do
    case hydrate_node(node) do
      {:ok, hydrated} -> hydrated
      :error -> raise ArgumentError, "invalid persisted node"
    end
  end

  def hydrate_edge(%NetworkDefense.Graph.Edge{} = edge) do
    with type when not is_nil(type) <- RelationshipRegistry.module_for(edge.type),
         {:ok, data} <- load_data(type, edge.data) do
      {:ok,
       %NetworkDefense.Graph.Domain.Edge{
         id: edge.id,
         graph_id: edge.graph_id,
         from_id: edge.from_id,
         to_id: edge.to_id,
         type: type,
         data: data
       }}
    else
      _ -> :error
    end
  end

  def hydrate_edge!(edge) do
    case hydrate_edge(edge) do
      {:ok, hydrated} -> hydrated
      :error -> raise ArgumentError, "invalid persisted edge"
    end
  end

  def persist_node(%NetworkDefense.Graph.Domain.Node{} = node) do
    %NetworkDefense.Graph.Node{
      id: node.id,
      graph_id: node.graph_id,
      type: NodeRegistry.type_for(node.type),
      data: data_params(node.data),
      view_data: ViewData.to_params(node.view_data)
    }
  end

  def persist_edge(%NetworkDefense.Graph.Domain.Edge{} = edge) do
    %NetworkDefense.Graph.Edge{
      id: edge.id,
      graph_id: edge.graph_id,
      from_id: edge.from_id,
      to_id: edge.to_id,
      type: RelationshipRegistry.type_for(edge.type),
      data: data_params(edge.data)
    }
  end

  def data_params(data) when is_struct(data) do
    data
    |> Map.from_struct()
    |> Map.drop([:__meta__])
    |> Map.new(fn {key, value} -> {Atom.to_string(key), data_value(value)} end)
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp load_data(schema, data) do
    schema
    |> struct()
    |> schema.changeset(data || %{})
    |> Changeset.apply_action(:validate)
  end

  defp data_value(nil), do: nil
  defp data_value(value) when is_atom(value), do: Atom.to_string(value)
  defp data_value(value), do: value
end
