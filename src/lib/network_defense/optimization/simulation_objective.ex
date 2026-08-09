defmodule NetworkDefense.Optimization.SimulationObjective do
  @moduledoc false

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.MaterializeReachability
  alias NetworkDefense.Simulation.{Run, Simulator}

  @doc "Number of foothold nodes held at the end of a run."
  @spec final_foothold_count(Run.t()) :: non_neg_integer()
  def final_foothold_count(run) do
    run |> Run.current_attacker_state() |> AttackerState.foothold_nodes() |> length()
  end

  def expected_blast_radius(graph, strategy) do
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
    |> Enum.map(&final_foothold_count/1)
    |> then(&(Enum.sum(&1) / length(&1)))
  end
end
