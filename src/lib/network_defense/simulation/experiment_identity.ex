defmodule NetworkDefense.Simulation.ExperimentIdentity do
  @moduledoc false

  alias NetworkDefense.Simulation.Contracts.RunSimulationRequest
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Seed

  # The identity of one stored experiment.
  #
  # A stored experiment represents the graph revision, the trial count, the
  # iterations per run, the maximum attempts, the initial foothold, and the
  # master seed. The request declares the same scientific fields, so a stored
  # experiment answers a request only when those fields are equal.
  #
  # A declared seed is part of the identity. A generated seed is not: the
  # request declares no concrete seed, and the stored experiment holds the
  # realization that the generator chose. A repeated request therefore reuses a
  # generated-seed experiment instead of drawing a second seed.
  #
  # The correlation identifier and the runtime status are operational metadata,
  # so neither is part of the identity.

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
      initial_foothold_node_id: params.initial_foothold_node_id
    )
  end

  @spec check(Experiment.t(), RunSimulationRequest.t()) :: :ok | {:error, :request_mismatch}
  def check(%Experiment{} = experiment, %RunSimulationRequest{} = request) do
    if stored(experiment) == declared(request) and seed_matches?(experiment, request) do
      :ok
    else
      {:error, :request_mismatch}
    end
  end

  @spec declared(RunSimulationRequest.t()) :: map()
  def declared(%RunSimulationRequest{} = request) do
    params = request.simulation_params

    %{
      graph_revision_id: request.graph_revision_id,
      total_trials: params.monte_carlo_trials,
      iteration_count: params.iterations_per_run,
      max_attempts: params.max_attempts,
      initial_foothold_node_id: params.initial_foothold_node_id
    }
  end

  @spec stored(Experiment.t()) :: map()
  def stored(%Experiment{} = experiment) do
    %{
      graph_revision_id: experiment.graph_revision_id,
      total_trials: experiment.total_trials,
      iteration_count: experiment.iteration_count,
      max_attempts: experiment.max_attempts,
      initial_foothold_node_id: experiment.initial_foothold_node_id
    }
  end

  defp seed_matches?(
         %Experiment{},
         %RunSimulationRequest{simulation_params: %{generate_seed: true}}
       ),
       do: true

  defp seed_matches?(
         %Experiment{master_seed: stored_seed},
         %RunSimulationRequest{simulation_params: %{generate_seed: false, seed: requested_seed}}
       ),
       do: Seed.equal?(stored_seed, requested_seed)
end
