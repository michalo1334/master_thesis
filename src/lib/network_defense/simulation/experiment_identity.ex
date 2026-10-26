defmodule NetworkDefense.Simulation.ExperimentIdentity do
  @moduledoc false

  alias NetworkDefense.Simulation.Contracts.RunSimulationRequest
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Seed

  @doc false
  @spec new(RunSimulationRequest.t()) :: Experiment.t()
  def new(%RunSimulationRequest{} = request) do
    params = request.simulation_params
    seed = if params.generate_seed, do: Seed.random(), else: params.seed

    Experiment.new(
      graph_revision_id: request.graph_revision_id,
      master_seed: seed,
      iteration_count: params.iterations_per_run,
      max_attempts: params.max_attempts,
      total_trials: params.monte_carlo_trials,
      initial_foothold_node_id: params.initial_foothold_node_id,
      rules: params.rules,
      require_pre_attack_feasibility: params.require_pre_attack_feasibility
    )
  end
end
