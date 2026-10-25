defmodule NetworkDefense.Optimization.RunIdentity do
  @moduledoc false

  alias NetworkDefense.Optimization.Contracts.RunOptimizationRequest
  alias NetworkDefense.Optimization.OptimizationRun

  # The identity of one stored optimization run.
  #
  # A stored run answers a request only when the request names the same graph
  # revision, strategy, budget, concrete seed, and simulation configuration.
  # The correlation identifier is operational metadata, so it is not part of
  # the identity.
  #
  # `Optimizations.run_or_resume/2` and the study runtime reservation both check
  # a run against a request through this module, so one rule decides the
  # identity and a resume cannot accept what a reservation rejects.

  @doc false
  @spec new(RunOptimizationRequest.t()) :: OptimizationRun.t()
  def new(%RunOptimizationRequest{} = request) do
    OptimizationRun.new(
      graph_revision_id: request.graph_revision_id,
      strategy: request.optimization_params.strategy,
      requested_budget: request.optimization_params.budget,
      seed: request.optimization_params.seed,
      simulation_config: simulation_config(request)
    )
  end

  @spec check(OptimizationRun.t(), RunOptimizationRequest.t()) ::
          :ok | {:error, :request_mismatch}
  def check(%OptimizationRun{} = run, %RunOptimizationRequest{} = request) do
    if declared(request) == stored(run), do: :ok, else: {:error, :request_mismatch}
  end

  @spec declared(RunOptimizationRequest.t()) :: map()
  def declared(%RunOptimizationRequest{} = request) do
    %{
      graph_revision_id: request.graph_revision_id,
      strategy: request.optimization_params.strategy,
      budget: request.optimization_params.budget,
      seed: request.optimization_params.seed,
      simulation_config: simulation_config(request)
    }
  end

  @spec stored(OptimizationRun.t()) :: map()
  def stored(%OptimizationRun{} = run) do
    %{
      graph_revision_id: run.graph_revision_id,
      strategy: run.strategy,
      budget: run.requested_budget,
      seed: run.seed,
      simulation_config: run.simulation_config
    }
  end

  @doc "The persisted simulation settings of the request, or `nil` when it declares none."
  @spec simulation_config(RunOptimizationRequest.t()) :: map() | nil
  def simulation_config(%RunOptimizationRequest{optimization_params: %{simulation_params: nil}}),
    do: nil

  def simulation_config(%RunOptimizationRequest{optimization_params: params}) do
    %{
      "monte_carlo_trials" => params.simulation_params.monte_carlo_trials,
      "iterations_per_run" => params.simulation_params.iterations_per_run,
      "initial_foothold_node_id" => params.simulation_params.initial_foothold_node_id,
      "max_attempts" => params.simulation_params.max_attempts
    }
  end
end
