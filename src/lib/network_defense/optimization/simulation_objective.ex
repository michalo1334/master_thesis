defmodule NetworkDefense.Optimization.SimulationObjective do
  @moduledoc false

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.MaterializeReachability
  alias NetworkDefense.Simulation.{Run, Simulator}

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
    |> Enum.map(fn run ->
      run |> Run.current_attacker_state() |> AttackerState.foothold_nodes() |> length()
    end)
    |> then(&(Enum.sum(&1) / length(&1)))
  end
end
