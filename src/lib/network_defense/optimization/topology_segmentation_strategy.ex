defmodule NetworkDefense.Optimization.TopologySegmentationStrategy do
  @moduledoc false

  alias NetworkDefense.DefenseActions.BlockReachability
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Optimization.{Budget, Strategy}
  alias NetworkDefense.Simulations

  defstruct [:initial_foothold_node_id]

  def new(graph, %{simulation_params: simulation_params}) do
    with :ok <-
           Simulations.validate_initial_foothold(
             graph,
             simulation_params.initial_foothold_node_id
           ) do
      {:ok, %__MODULE__{initial_foothold_node_id: simulation_params.initial_foothold_node_id}}
    end
  end

  defimpl Strategy, for: __MODULE__ do
    alias NetworkDefense.Graph.Query
    alias NetworkDefense.Nodes.{Host, Service}
    alias NetworkDefense.Relationships.{NetworkReachability, Runs}

    @spec name(Strategy.t()) :: String.t()
    def name(_strategy), do: "Topology segmentation strategy"

    @spec rank(Strategy.t(), [module()], Graph.t(), Budget.t()) :: list()
    def rank(strategy, action_types, graph, _budget) do
      if BlockReachability in action_types do
        host_links = host_links(graph)
        reachable_count = reachable_host_count(strategy.initial_foothold_node_id, host_links, nil)

        graph
        |> Graph.edges()
        |> Enum.filter(&(&1.type == NetworkReachability))
        |> Enum.map(fn edge ->
          reduction =
            reachable_count -
              reachable_host_count(strategy.initial_foothold_node_id, host_links, edge.id)

          {%BlockReachability{edge_id: edge.id}, reduction}
        end)
        |> Enum.filter(fn {_action, reduction} -> reduction > 0 end)
        |> Enum.sort_by(fn {%BlockReachability{edge_id: edge_id}, reduction} ->
          {-reduction, edge_id}
        end)
        |> Enum.map(&elem(&1, 0))
      else
        []
      end
    end

    defp host_links(graph) do
      graph
      |> Query.match(%{
        start: {:source_host, Host},
        hops: [
          %{via: {:reachability, NetworkReachability}, to: {:service, Service}}
        ],
        joins: [
          %{from: {:target_host, Host}, via: {:runs, Runs}, to: {:service, Service}}
        ]
      })
      |> Enum.map(fn match ->
        {match.source_host.id, match.target_host.id, match.reachability.id}
      end)
    end

    defp reachable_host_count(source_id, links, blocked_edge_id) do
      adjacency =
        Enum.reduce(links, %{}, fn {link_source_id, target_id, edge_id}, adjacency ->
          if edge_id == blocked_edge_id do
            adjacency
          else
            Map.update(adjacency, link_source_id, [target_id], &[target_id | &1])
          end
        end)

      traverse([source_id], adjacency, MapSet.new()) |> MapSet.size()
    end

    defp traverse([], _adjacency, visited), do: visited

    defp traverse([host_id | rest], adjacency, visited) do
      if MapSet.member?(visited, host_id) do
        traverse(rest, adjacency, visited)
      else
        traverse(Map.get(adjacency, host_id, []) ++ rest, adjacency, MapSet.put(visited, host_id))
      end
    end
  end
end
