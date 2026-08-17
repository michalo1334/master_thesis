defmodule NetworkDefense.Optimization.SimulationObjective do
  @moduledoc false

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.MaterializeReachability
  alias NetworkDefense.Simulation.{Run, Simulator}
  alias NetworkDefense.Simulation.MissionImpact

  @doc "Number of foothold nodes held at the end of a run."
  @spec final_foothold_count(Run.t()) :: non_neg_integer()
  def final_foothold_count(run) do
    run |> Run.current_attacker_state() |> AttackerState.foothold_nodes() |> length()
  end

  @doc "Whether every mission capability remains operational before an attack."
  @spec feasible?(Graph.t()) :: boolean()
  def feasible?(graph) do
    graph
    |> MissionImpact.capability_statuses([])
    |> Enum.all?(&(not &1.down?))
  end

  @doc "Expected {mission impact, blast radius} from one experiment."
  @spec expected(Graph.t(), map()) :: {float(), float()}
  def expected(graph, strategy) do
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

    {mission_impacts, blast_radii} =
      runs
      |> Enum.map(fn run ->
        footholds = run |> Run.current_attacker_state() |> AttackerState.foothold_nodes()
        {MissionImpact.final(graph, footholds), length(footholds)}
      end)
      |> Enum.unzip()

    {Enum.sum(mission_impacts) / length(mission_impacts),
     Enum.sum(blast_radii) / length(blast_radii)}
  end
end
