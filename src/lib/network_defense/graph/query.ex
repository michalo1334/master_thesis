defmodule NetworkDefense.Graph.Query do
  @moduledoc """
  A mini DSL that models Cypher queries syntax via small set of generic functions. Simplifies graph operations.
  """

  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Nodes.Registry, as: NodeRegistry
  alias NetworkDefense.Relationships.Registry, as: RelationshipRegistry

  def match(%Graph{} = graph, %{start: start, hops: hops}) when is_list(hops) do
    initial_rows =
      graph
      |> match_nodes(start)
      |> Enum.map(&new_row(start, &1))

    hops
    |> Enum.reduce(initial_rows, fn hop, rows -> expand_join(graph, rows, hop) end)
    |> Enum.map(& &1.bindings)
  end

  defp match_nodes(graph, matcher) do
    Enum.filter(Graph.nodes(graph), &matches?(&1, matcher))
  end

  defp expand_join(graph, rows, %{via: via, to: to}) do
    Enum.flat_map(rows, fn row ->
      graph
      |> Graph.outgoing(row.current.id)
      |> Enum.flat_map(&extend_join(graph, row, via, to, &1))
    end)
  end

  defp extend_join(graph, row, via, to, {target_id, edge}) do
    with %Node{} = target <- Graph.node(graph, target_id),
         true <- matches?(edge, via),
         true <- matches?(target, to) do
      [%{row | current: target} |> bind(via, edge) |> bind(to, target)]
    else
      _ -> []
    end
  end

  defp matches?(%Node{} = node, matcher) do
    matches_type?(node, node.type, NodeRegistry, matcher)
  end

  defp matches?(%Edge{} = edge, matcher) do
    matches_type?(edge, edge.type, RelationshipRegistry, matcher)
  end

  defp matches_type?(_value, stored_type, registry, {_variable, type}) do
    stored_type == type_id!(registry, type)
  end

  defp matches_type?(value, stored_type, registry, {_variable, type, predicate})
       when is_function(predicate, 1) do
    stored_type == type_id!(registry, type) and predicate.(value)
  end

  defp new_row(matcher, node) do
    %{current: node, bindings: %{}}
    |> bind(matcher, node)
  end

  defp bind(row, {nil, _type}, _value), do: row
  defp bind(row, {nil, _type, _predicate}, _value), do: row

  defp bind(row, {variable, _type}, value) do
    %{row | bindings: Map.put(row.bindings, variable, value)}
  end

  defp bind(row, {variable, _type, _predicate}, value) do
    %{row | bindings: Map.put(row.bindings, variable, value)}
  end

  defp type_id!(registry, module) do
    case registry.type_for(module) do
      nil -> raise ArgumentError, "unregistered graph type: #{inspect(module)}"
      type -> type
    end
  end
end
