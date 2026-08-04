defmodule NetworkDefense.Simulation.CharacterizationBaselineTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.MaterializeReachability
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Simulation.Run
  alias NetworkDefense.Simulation.SimulationReport
  alias NetworkDefense.Simulation.Simulator
  alias NetworkDefense.Simulations
  alias NetworkDefense.Topology.EnterpriseTopology

  @topology_seed 7
  @simulation_seed 42
  @iteration_count 50
  @run_count 200
  @graph_id "baseline-graph"

  describe "Phase 0 blast-radius baseline" do
    test "pins the seeded blast-radius distribution and mean on the normalized operational graph" do
      graph =
        EnterpriseTopology.generate(hosts: 8, seed: @topology_seed)
        |> normalize_graph()
        |> MaterializeReachability.materialize()

      foothold = Enum.find(Graph.nodes(graph), &(&1.data.name == "internet"))

      {experiment, runs} =
        Simulator.run_experiment(
          graph,
          AttackerState.new(foothold.id),
          rules: Simulations.default_rules(),
          iteration_count: @iteration_count,
          seed: @simulation_seed,
          run_count: @run_count
        )

      distribution =
        runs
        |> Enum.map(fn run ->
          run
          |> Run.current_attacker_state()
          |> AttackerState.foothold_nodes()
          |> length()
        end)
        |> Enum.frequencies()

      assert Enum.sum(Map.values(distribution)) == @run_count
      assert distribution == %{1 => 42, 2 => 54, 3 => 73, 4 => 31}

      assert %{
               expected_blast_radius: 2.465,
               median_blast_radius: 3,
               min_blast_radius: 1,
               max_blast_radius: 4
             } = SimulationReport.generate(%{experiment | graph: graph}).summary
    end

    test "reproduces the same blast-radius distribution across two independently normalized graphs" do
      graphs =
        for _ <- 1..2 do
          EnterpriseTopology.generate(hosts: 8, seed: @topology_seed)
          |> normalize_graph()
          |> MaterializeReachability.materialize()
        end

      distributions = Enum.map(graphs, fn graph -> {graph, run_scenario(graph)} end)

      for {graph, distribution} <- distributions do
        assert distribution == %{1 => 42, 2 => 54, 3 => 73, 4 => 31}
        assert graph |> Graph.nodes() |> Enum.count(&(&1.type == Host)) == 9
        assert Enum.any?(Graph.nodes(graph), &(&1.data.name == "internet"))
      end

      assert distributions
             |> Enum.map(&elem(&1, 1))
             |> Enum.uniq()
             |> length() == 1
    end
  end

  defp run_scenario(graph) do
    foothold = Enum.find(Graph.nodes(graph), &(&1.data.name == "internet"))

    {_experiment, runs} =
      Simulator.run_experiment(
        graph,
        AttackerState.new(foothold.id),
        rules: Simulations.default_rules(),
        iteration_count: @iteration_count,
        seed: @simulation_seed,
        run_count: @run_count
      )

    runs
    |> Enum.map(fn run ->
      run
      |> Run.current_attacker_state()
      |> AttackerState.foothold_nodes()
      |> length()
    end)
    |> Enum.frequencies()
  end

  # Rebuilds the graph with stable index/name-derived IDs so the simulator's
  # action sort order no longer depends on the random UUIDs of a given draw.
  # The graph id and every node/edge graph_id are pinned too because the
  # materialized operational edge ids are derived from the graph id.
  defp normalize_graph(graph) do
    graph = %{graph | id: @graph_id}

    {nodes, id_by_old} =
      graph
      |> Graph.nodes()
      |> Enum.with_index(1)
      |> Enum.map_reduce(%{}, fn {node, index}, acc ->
        id = "node-#{index}"
        {%{node | id: id, graph_id: @graph_id}, Map.put(acc, node.id, id)}
      end)

    edges =
      graph
      |> Graph.edges()
      |> Enum.sort_by(fn edge -> {edge.from_id, edge.to_id, edge.type} end)
      |> Enum.with_index(1)
      |> Enum.map(fn {edge, index} ->
        from_id = Map.fetch!(id_by_old, edge.from_id)
        to_id = Map.fetch!(id_by_old, edge.to_id)

        %{
          edge
          | id: "edge-#{index}",
            graph_id: @graph_id,
            from_id: from_id,
            to_id: to_id
        }
      end)

    {:ok, graph} = Graph.hydrate(graph, nodes, edges, false)
    graph
  end
end
