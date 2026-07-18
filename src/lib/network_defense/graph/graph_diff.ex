defmodule NetworkDefense.Graph.GraphDiff do
  @moduledoc """
  Compares complete graph states by stable node and edge IDs.
  """

  alias NetworkDefense.Graph.Graph

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
    Enum.flat_map(fields, fn {field, previous, candidate} ->
      if previous == candidate, do: [], else: [field]
    end)
  end

  defp entity_diff_empty?(diff),
    do: diff.added == [] and diff.removed == [] and diff.changed == []

  defp index_by_id(entities), do: Map.new(entities, &{&1.id, &1})
end
