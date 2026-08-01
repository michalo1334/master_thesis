defmodule NetworkDefense.Graph.GraphDiff do
  @moduledoc """
  Compares complete graph states by stable node and edge IDs.
  """

  alias NetworkDefense.Graph.{Data, Graph}

  def compare(%Graph{} = previous, %Graph{} = candidate) do
    previous_nodes = index_by_id(Graph.nodes(previous))
    candidate_nodes = index_by_id(Graph.nodes(candidate))
    previous_edges = index_by_id(Graph.edges(previous))
    candidate_edges = index_by_id(Graph.edges(candidate))

    %{
      title_changed: previous.title != candidate.title,
      nodes:
        compare_entities(previous_nodes, candidate_nodes, fn _id, left, right ->
          changed_fields([
            {:type, left.type, right.type},
            {:data, left.data, right.data},
            {:view_data, left.view_data, right.view_data}
          ])
        end),
      edges:
        compare_entities(previous_edges, candidate_edges, fn _id, left, right ->
          changed_fields([
            {:from_id, left.from_id, right.from_id},
            {:to_id, left.to_id, right.to_id},
            {:type, left.type, right.type},
            {:data, left.data, right.data}
          ])
        end)
    }
  end

  def empty?(diff) do
    not diff.title_changed and entity_diff_empty?(diff.nodes) and entity_diff_empty?(diff.edges)
  end

  @doc """
  Compares graph topology while ignoring graph metadata and node view data.
  """
  def structural(%Graph{} = base, %Graph{} = candidate) do
    base_nodes = Graph.nodes(base)
    candidate_nodes = Graph.nodes(candidate)
    node_matches = match_nodes(base_nodes, candidate_nodes)
    node_status = node_status(base_nodes, node_matches)
    node_display_ids = display_ids(base_nodes, candidate_nodes, node_matches)

    nodes =
      Enum.map(base_nodes, &{&1, Map.fetch!(node_status, &1.id)}) ++
        (candidate_nodes
         |> Enum.reject(&Map.has_key?(node_matches.candidate, &1.id))
         |> Enum.map(fn node ->
           {%{node | id: Map.fetch!(node_display_ids, node.id), graph_id: base.id}, "added"}
         end))

    base_edges = Graph.edges(base)
    candidate_edges = Graph.edges(candidate)
    edge_matches = match_edges(base_edges, candidate_edges, base_nodes, candidate_nodes)
    edge_display_ids = display_ids(base_edges, candidate_edges, edge_matches)

    edges =
      Enum.map(base_edges, &{&1, edge_status(&1.id, edge_matches.base)}) ++
        (candidate_edges
         |> Enum.reject(&Map.has_key?(edge_matches.candidate, &1.id))
         |> Enum.map(fn edge ->
           {%{
              edge
              | id: Map.fetch!(edge_display_ids, edge.id),
                graph_id: base.id,
                from_id: Map.fetch!(node_display_ids, edge.from_id),
                to_id: Map.fetch!(node_display_ids, edge.to_id)
            }, "added"}
         end))

    %{
      graph:
        Graph.hydrate(
          %{base | nodes: [], edges: [], adjacency_list: %{}},
          entity_values(nodes),
          entity_values(edges)
        ),
      node_status: status_entries(nodes),
      node_counts: status_counts(nodes),
      edge_status: status_entries(edges),
      edge_counts: status_counts(edges)
    }
  end

  defp compare_entities(previous, candidate, changed_fields) do
    previous_ids = previous |> Map.keys() |> MapSet.new()
    candidate_ids = candidate |> Map.keys() |> MapSet.new()

    changed =
      previous_ids
      |> MapSet.intersection(candidate_ids)
      |> Enum.sort()
      |> Enum.flat_map(fn id ->
        case changed_fields.(id, Map.fetch!(previous, id), Map.fetch!(candidate, id)) do
          [] -> []
          fields -> [%{id: id, fields: fields}]
        end
      end)

    %{
      added: candidate_ids |> MapSet.difference(previous_ids) |> Enum.sort(),
      removed: previous_ids |> MapSet.difference(candidate_ids) |> Enum.sort(),
      changed: changed
    }
  end

  defp changed_fields(fields) do
    for {field, previous, candidate} <- fields, previous != candidate, do: field
  end

  defp entity_diff_empty?(diff),
    do: diff.added == [] and diff.removed == [] and diff.changed == []

  defp index_by_id(entities), do: Map.new(entities, &{&1.id, &1})

  defp match_nodes(base, candidate) do
    match_groups(group_by_key(base, &node_key/1), group_by_key(candidate, &node_key/1))
  end

  defp match_edges(base, candidate, base_nodes, candidate_nodes) do
    base_node_keys = Map.new(base_nodes, &{&1.id, node_key(&1)})
    candidate_node_keys = Map.new(candidate_nodes, &{&1.id, node_key(&1)})

    match_groups(
      group_by_key(base, &edge_key(&1, base_node_keys)),
      group_by_key(candidate, &edge_key(&1, candidate_node_keys))
    )
  end

  defp match_groups(base_by_key, candidate_by_key) do
    Enum.reduce(base_by_key, %{base: %{}, candidate: %{}}, fn {key, base_entities}, matches ->
      candidate_entities = Map.get(candidate_by_key, key, [])

      Enum.zip(base_entities, candidate_entities)
      |> Enum.reduce(matches, fn {base_entity, candidate_entity}, matches ->
        %{
          base: Map.put(matches.base, base_entity.id, candidate_entity.id),
          candidate: Map.put(matches.candidate, candidate_entity.id, base_entity.id)
        }
      end)
    end)
  end

  defp group_by_key(entities, key) do
    entities
    |> Enum.group_by(key)
    |> Map.new(fn {group_key, group} -> {group_key, Enum.sort_by(group, & &1.id)} end)
  end

  defp node_status(base, matches) do
    Map.new(base, &{&1.id, edge_status(&1.id, matches.base)})
  end

  defp display_ids(base, candidate, matches) do
    base_ids = base |> Enum.map(& &1.id) |> MapSet.new()
    reserved_ids = (base ++ candidate) |> Enum.map(& &1.id) |> MapSet.new()

    {display_ids, _reserved_ids} =
      Enum.reduce(candidate, {%{}, reserved_ids}, fn entity, {display_ids, reserved_ids} ->
        case Map.get(matches.candidate, entity.id) do
          nil ->
            {id, reserved_ids} = unmatched_display_id(entity.id, base_ids, reserved_ids)
            {Map.put(display_ids, entity.id, id), reserved_ids}

          base_id ->
            {Map.put(display_ids, entity.id, base_id), reserved_ids}
        end
      end)

    display_ids
  end

  defp unmatched_display_id(id, base_ids, reserved_ids) do
    if MapSet.member?(base_ids, id) do
      id = fresh_id(reserved_ids)
      {id, MapSet.put(reserved_ids, id)}
    else
      {id, reserved_ids}
    end
  end

  defp fresh_id(reserved_ids) do
    id = Ecto.UUID.generate()
    if MapSet.member?(reserved_ids, id), do: fresh_id(reserved_ids), else: id
  end

  defp edge_status(id, matches),
    do: if(Map.has_key?(matches, id), do: "unchanged", else: "removed")

  defp entity_values(entities), do: Enum.map(entities, &elem(&1, 0))

  defp status_entries(entities),
    do: Enum.map(entities, fn {entity, status} -> %{id: entity.id, status: status} end)

  defp status_counts(entities) do
    Enum.reduce(entities, %{added: 0, removed: 0, unchanged: 0}, fn {_entity, status}, counts ->
      Map.update!(counts, String.to_existing_atom(status), &(&1 + 1))
    end)
  end

  defp node_key(node), do: {type_key(node.type), canonical(node.data)}

  defp relationship_key(edge), do: {type_key(edge.type), canonical(edge.data)}

  defp edge_key(edge, node_keys),
    do:
      {relationship_key(edge), Map.fetch!(node_keys, edge.from_id),
       Map.fetch!(node_keys, edge.to_id)}

  defp type_key(type) when is_atom(type), do: Atom.to_string(type)
  defp type_key(type), do: type

  defp canonical(value) when is_struct(value), do: value |> Data.to_params() |> canonical()
  defp canonical(nil), do: "null"
  defp canonical(value) when is_binary(value), do: inspect(value)
  defp canonical(value) when is_integer(value), do: Integer.to_string(value)
  defp canonical(value) when is_float(value), do: :erlang.float_to_binary(value, [:compact])
  defp canonical(value) when is_atom(value), do: Atom.to_string(value)
  defp canonical(value) when is_list(value), do: "[#{Enum.map_join(value, ",", &canonical/1)}]"

  defp canonical(value) when is_map(value) do
    "{" <>
      (value
       |> Enum.map(fn {key, item} -> {to_string(key), item} end)
       |> Enum.sort_by(&elem(&1, 0))
       |> Enum.map_join(",", fn {key, item} -> "#{inspect(key)}:#{canonical(item)}" end)) <> "}"
  end
end
