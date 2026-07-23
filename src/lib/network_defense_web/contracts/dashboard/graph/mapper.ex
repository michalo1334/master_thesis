defmodule NetworkDefenseWeb.Web.Contracts.GraphMapper do
  @moduledoc false

  alias NetworkDefense.Graph.Graph
  alias NetworkDefenseWeb.Contracts
  alias NetworkDefenseWeb.Web.Contracts.GraphContract

  def to_wire(graph) do
    with {:ok, contract} <- from_graph(graph) do
      {:ok, GraphContract.to_wire(contract)}
    end
  end

  def from_graph(graph) do
    GraphContract.validate(%{
      id: graph.id,
      title: graph.title,
      lock_version: graph.lock_version,
      nodes: Enum.map(Graph.nodes(graph), &node_from_domain/1),
      edges: Enum.map(Graph.edges(graph), &edge_from_domain/1)
    })
  end

  def to_attrs(%GraphContract{} = graph) do
    %{
      "title" => graph.title,
      "nodes" => Enum.map(graph.nodes, &node_to_attrs/1),
      "edges" => Enum.map(graph.edges, &edge_to_attrs/1)
    }
  end

  defp node_from_domain(node) do
    %{
      id: node.id,
      type: short_type(node.type),
      data: node.data,
      view_data: %{
        x_pos: Map.get(node.view_data, :x_pos) || Map.get(node.view_data, "x_pos"),
        y_pos: Map.get(node.view_data, :y_pos) || Map.get(node.view_data, "y_pos"),
        radius: Map.get(node.view_data, :radius) || Map.get(node.view_data, "radius")
      }
    }
  end

  defp edge_from_domain(edge) do
    %{
      id: edge.id,
      from_id: edge.from_id,
      to_id: edge.to_id,
      type: short_type(edge.type),
      data: edge.data
    }
  end

  defp node_to_attrs(node) do
    %{
      "id" => node.id,
      "type" => node.type,
      "data" => Contracts.to_params(node.data),
      "view_data" =>
        node.view_data
        |> Contracts.to_params()
        |> Map.reject(fn {_key, value} -> is_nil(value) end)
    }
  end

  defp edge_to_attrs(edge) do
    %{
      "id" => edge.id,
      "from_id" => edge.from_id,
      "to_id" => edge.to_id,
      "type" => edge.type,
      "data" => Contracts.to_params(edge.data)
    }
  end

  defp short_type(module), do: module |> Module.split() |> List.last()
end
