defmodule NetworkDefense.Optimization.TopologySegmentationStrategy do
  @moduledoc false

  alias NetworkDefense.DefenseActions.BlockSegmentReachability
  alias NetworkDefense.Graph.{Graph, MaterializeReachability}
  alias NetworkDefense.Optimization.{Budget, Strategy}
  alias NetworkDefense.Relationships.{NetworkReachability, Runs, SegmentReachability}
  alias NetworkDefense.Simulations

  defstruct [:initial_foothold_node_id]

  def new(graph, %{simulation_params: simulation_params}) do
    with :ok <-
           Simulations.validate_initial_foothold(
             graph,
             simulation_params.initial_foothold_node_id
           ),
         :ok <- ensure_reachability(graph) do
      {:ok, %__MODULE__{initial_foothold_node_id: simulation_params.initial_foothold_node_id}}
    end
  end

  defp ensure_reachability(graph) do
    if graph
       |> Graph.edges()
       |> Enum.any?(&(&1.type == SegmentReachability)) do
      :ok
    else
      {:error, "topology segmentation requires reachability relationships in the graph"}
    end
  end

  defimpl Strategy, for: __MODULE__ do
    @spec name(Strategy.t()) :: String.t()
    def name(_strategy), do: "Topology segmentation strategy"

    @spec rank(Strategy.t(), [module()], Graph.t(), Budget.t()) :: list()
    def rank(strategy, action_types, graph, _budget) do
      if BlockSegmentReachability in action_types do
        baseline = reachable_host_count(strategy.initial_foothold_node_id, graph)

        graph
        |> Graph.edges()
        |> Enum.filter(&(&1.type == SegmentReachability))
        |> Enum.map(fn edge ->
          reduction =
            baseline -
              reachable_host_count(
                strategy.initial_foothold_node_id,
                Graph.remove_edge_by_id(graph, edge.id)
              )

          {%BlockSegmentReachability{edge_id: edge.id}, reduction}
        end)
        |> Enum.filter(fn {_action, reduction} -> reduction > 0 end)
        |> Enum.sort_by(fn {%BlockSegmentReachability{edge_id: edge_id}, reduction} ->
          {-reduction, edge_id}
        end)
        |> Enum.map(&elem(&1, 0))
      else
        []
      end
    end

    # ponytail: exact but O(policies * flows): rematerializes and BFSes the full
    # graph per candidate. Parallelize per policy or diff flows incrementally once
    # real graph sizes warrant profiling.
    defp reachable_host_count(foothold_id, graph) do
      hosts_by_service =
        Enum.flat_map(Graph.edges(graph), fn
          %{type: Runs, from_id: host_id, to_id: service_id} -> [{service_id, host_id}]
          _ -> []
        end)
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

      adjacency =
        graph
        |> MaterializeReachability.materialize()
        |> Graph.edges()
        |> Enum.reduce(%{}, fn
          %{type: NetworkReachability, from_id: source_id, to_id: service_id}, adjacency ->
            target_hosts = Map.get(hosts_by_service, service_id, [])
            Map.update(adjacency, source_id, target_hosts, &(target_hosts ++ &1))

          _edge, adjacency ->
            adjacency
        end)

      traverse([foothold_id], adjacency, %{}) |> map_size()
    end

    defp traverse([], _adjacency, visited), do: visited

    defp traverse([host_id | rest], adjacency, visited) do
      if Map.has_key?(visited, host_id) do
        traverse(rest, adjacency, visited)
      else
        traverse(
          Map.get(adjacency, host_id, []) ++ rest,
          adjacency,
          Map.put(visited, host_id, true)
        )
      end
    end
  end
end
