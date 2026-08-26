defmodule NetworkDefense.Optimization.SimulationObjective do
  @moduledoc false

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.MaterializeReachability
  alias NetworkDefense.Simulation.{MissionImpact, Run, Simulator}

  @objectives [:blast_radius_only, :mission_impact_only, :mission_then_blast_radius]
  @wire_objectives Enum.map(@objectives, &Atom.to_string/1)

  @type t :: :blast_radius_only | :mission_impact_only | :mission_then_blast_radius

  @spec from_wire(String.t()) :: {:ok, t()} | :error
  def from_wire(wire) when wire in @wire_objectives, do: {:ok, String.to_existing_atom(wire)}
  def from_wire(_wire), do: :error

  @spec to_wire(t()) :: String.t()
  def to_wire(objective), do: Atom.to_string(objective)

  @doc "Number of foothold nodes held at the end of a run."
  @spec final_foothold_count(Run.t()) :: non_neg_integer()
  def final_foothold_count(run) do
    run |> Run.current_attacker_state() |> AttackerState.foothold_nodes() |> length()
  end

  @doc """
  Ranks expected {mission impact, blast radius} for a validated objective.
  Lower tuples win; `cost` is appended as the final tie breaker.
  """
  @spec ranking_key({float(), float()}, t(), number()) :: {float(), float(), number()}
  def ranking_key({_mission_impact, blast_radius}, :blast_radius_only, cost),
    do: {blast_radius, 0.0, cost}

  def ranking_key({mission_impact, _blast_radius}, :mission_impact_only, cost),
    do: {mission_impact, 0.0, cost}

  def ranking_key({mission_impact, blast_radius}, :mission_then_blast_radius, cost),
    do: {mission_impact, blast_radius, cost}

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
