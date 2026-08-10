defmodule NetworkDefense.Optimization.SimulationObjective do
  @moduledoc false

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.MaterializeReachability
  alias NetworkDefense.Simulation.{Run, Simulator}
  alias NetworkDefense.Simulation.MissionImpact

  @doc "Number of foothold nodes held at the end of a run."
  @spec final_foothold_count(Run.t()) :: non_neg_integer()
  def final_foothold_count(run) do
    run |> Run.current_attacker_state() |> AttackerState.foothold_nodes() |> length()
  end

  def expected_blast_radius(graph, strategy) do
    expected(graph, strategy, :blast_radius)
  end

  def expected_mission_impact(graph, strategy) do
    expected(graph, strategy, :mission_impact)
  end

  def expected(graph, strategy, objective) when objective in [:blast_radius, :mission_impact] do
    graph = MaterializeReachability.materialize(graph)

    {_experiment, runs} =
      Simulator.run_experiment(
        graph,
        strategy.initial_attacker_state,
        run_count: strategy.run_count,
        iteration_count: strategy.iteration_count,
        seed: strategy.seed,
        rules: strategy.rules,
        max_attempts: strategy.max_attempts
      )

    runs
    |> Enum.map(&final_metric(&1, graph, objective))
    |> then(&(Enum.sum(&1) / length(&1)))
  end

  def final_metric(run, _graph, :blast_radius), do: final_foothold_count(run)

  def final_metric(run, graph, :mission_impact) do
    run
    |> Run.current_attacker_state()
    |> AttackerState.foothold_nodes()
    |> then(&MissionImpact.final(graph, &1))
  end
end
