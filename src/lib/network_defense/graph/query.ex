defmodule NetworkDefense.Graph.Query do
  @moduledoc """
  A small, Cypher-like DSL for matching typed graph paths and joins.
  """

  alias NetworkDefense.Graph.{Edge, Node}
  alias NetworkDefense.Graph.Graph

  def match(%Graph{} = graph, %{start: start, hops: hops} = pattern) when is_list(hops) do
    joins = Map.get(pattern, :joins, [])
    graph = Graph.indexed(graph)
    nodes = graph.node_index
    edges_to = graph.edge_index

    initial_rows =
      graph
      |> match_nodes(start)
      |> Enum.map(&new_row(start, &1))

    rows =
      Enum.reduce(hops, initial_rows, fn hop, rows -> expand_join(graph, rows, hop, nodes) end)

    joins
    |> Enum.reduce(rows, fn join, rows -> join_rows(graph, rows, join, nodes, edges_to) end)
    |> Enum.map(& &1.bindings)
  end

  defp match_nodes(graph, matcher) do
    Enum.filter(Graph.nodes(graph), &matches?(&1, matcher))
  end

  defp expand_join(graph, rows, %{via: via, to: to}, nodes) do
    Enum.flat_map(rows, fn row ->
      graph
      |> Graph.outgoing(row.current.id)
      |> Enum.flat_map(&extend_join(row, via, to, &1, nodes))
    end)
  end

  defp extend_join(row, via, to, {target_id, edge}, nodes) do
    with %Node{} = target <- Map.get(nodes, target_id),
         true <- matches?(edge, via),
         true <- matches?(target, to),
         true <- binding_compatible?(row, via, edge),
         true <- binding_compatible?(row, to, target) do
      [%{row | current: target} |> bind(via, edge) |> bind(to, target)]
    else
      _ -> []
    end
  end

  defp join_rows(graph, rows, %{from: from, via: via, to: to}, nodes, edges_to) do
    Enum.flat_map(rows, fn row ->
      case fetch_binding(row, to) do
        %Node{} = target ->
          reverse_join(row, from, via, target, nodes, edges_to)

        _ ->
          forward_join(graph, row, from, via, to, nodes)
      end
    end)
  end

  defp fetch_binding(row, {variable, _type}), do: Map.get(row.bindings, variable)
  defp fetch_binding(row, {variable, _type, _predicate}), do: Map.get(row.bindings, variable)

  defp reverse_join(row, from, via, target, nodes, edges_to) do
    edges_to
    |> Map.get({target.id, matcher_type(via)}, [])
    |> Enum.flat_map(fn {source_id, edge} ->
      with %Node{} = source <- Map.get(nodes, source_id),
           true <- matches?(source, from),
           true <- matches?(edge, via),
           true <- binding_compatible?(row, from, source),
           true <- binding_compatible?(row, via, edge) do
        [row |> bind(from, source) |> bind(via, edge)]
      else
        _ -> []
      end
    end)
  end

  defp forward_join(graph, row, from, via, to, nodes) do
    graph
    |> match_nodes(from)
    |> Enum.flat_map(fn source ->
      graph
      |> Graph.outgoing(source.id)
      |> Enum.flat_map(&extend_join_from(row, from, via, to, source, &1, nodes))
    end)
  end

  defp extend_join_from(row, from, via, to, source, {target_id, edge}, nodes) do
    with %Node{} = target <- Map.get(nodes, target_id),
         true <- matches?(edge, via),
         true <- matches?(target, to),
         true <- binding_compatible?(row, from, source),
         true <- binding_compatible?(row, via, edge),
         true <- binding_compatible?(row, to, target) do
      [row |> bind(from, source) |> bind(via, edge) |> bind(to, target)]
    else
      _ -> []
    end
  end

  defp matches?(%Node{} = node, matcher) do
    matches_type?(node, node.type, matcher)
  end

  defp matches?(%Edge{} = edge, matcher) do
    matches_type?(edge, edge.type, matcher)
  end

  defp matcher_type({_variable, type}), do: type
  defp matcher_type({_variable, type, _predicate}), do: type

  defp matches_type?(_value, stored_type, {_variable, type}) do
    stored_type == type
  end

  defp matches_type?(value, stored_type, {_variable, type, predicate})
       when is_function(predicate, 1) do
    stored_type == type and predicate.(value)
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

  defp binding_compatible?(_row, {nil, _type}, _value), do: true
  defp binding_compatible?(_row, {nil, _type, _predicate}, _value), do: true

  defp binding_compatible?(row, {variable, _type}, value) do
    Map.get(row.bindings, variable, value) == value
  end

  defp binding_compatible?(row, {variable, _type, _predicate}, value) do
    Map.get(row.bindings, variable, value) == value
  end
end
