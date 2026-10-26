defmodule NetworkDefense.Optimization.RunIdentity do
  @moduledoc false

  alias NetworkDefense.Optimization.Contracts.RunOptimizationRequest
  alias NetworkDefense.Optimization.{ExecutionConfig, OptimizationRun}

  @doc false
  @spec new(RunOptimizationRequest.t()) :: OptimizationRun.t()
  def new(%RunOptimizationRequest{} = request) do
    OptimizationRun.new(
      graph_revision_id: request.graph_revision_id,
      strategy: request.optimization_params.strategy,
      requested_budget: request.optimization_params.budget,
      seed: request.optimization_params.seed,
      execution_config: execution_config(request)
    )
  end

  @doc "Rebuilds the creation request of a stored run from its persisted settings."
  @spec stored_request(OptimizationRun.t(), String.t()) ::
          {:ok, RunOptimizationRequest.t()} | {:error, :invalid_request}
  def stored_request(%OptimizationRun{} = run, correlation_id) do
    case RunOptimizationRequest.validate(%{
           graph_revision_id: run.graph_revision_id,
           correlation_id: correlation_id,
           optimization_params: stored_params(run)
         }) do
      {:ok, request} -> {:ok, request}
      {:error, _changeset} -> {:error, :invalid_request}
    end
  end

  @doc "The effective execution configuration of one creation request."
  @spec execution_config(RunOptimizationRequest.t()) :: ExecutionConfig.t()
  def execution_config(%RunOptimizationRequest{optimization_params: params}) do
    %ExecutionConfig{
      candidate_action_types: params.candidate_action_types,
      require_pre_attack_feasibility: params.require_pre_attack_feasibility,
      initial_foothold_node_id: params.initial_foothold_node_id,
      scoring: params.simulation_params
    }
  end

  defp stored_params(%OptimizationRun{} = run) do
    %ExecutionConfig{
      candidate_action_types: candidate_action_types,
      require_pre_attack_feasibility: require_pre_attack_feasibility,
      initial_foothold_node_id: initial_foothold_node_id,
      scoring: scoring
    } = run.execution_config

    %{
      strategy: run.strategy,
      budget: run.requested_budget,
      seed: run.seed,
      candidate_action_types: candidate_action_types,
      require_pre_attack_feasibility: require_pre_attack_feasibility,
      initial_foothold_node_id: initial_foothold_node_id,
      simulation_params: simulation_settings_attrs(scoring)
    }
  end

  defp simulation_settings_attrs(nil), do: nil
  defp simulation_settings_attrs(settings), do: Map.from_struct(settings)
end
