defmodule NetworkDefense.Analysis.CombinedAnalysisWorkflow do
  @moduledoc false

  @behaviour NetworkDefense.Workflows.Template

  alias NetworkDefense.Optimization.Contracts.{OptimizationParams, RunOptimizationRequest}
  alias NetworkDefense.Optimizations
  alias NetworkDefense.Simulation.Contracts.SimulationParams
  alias NetworkDefense.Simulations
  alias NetworkDefense.Workflows

  @template "combined_analysis"
  @baseline_step "baseline_simulation"
  @optimization_step "optimization"
  @post_optimization_step "post_optimization_simulation"

  def template, do: @template

  def start(graph_revision_id, correlation_id, simulation_params, optimization_params) do
    input = %{
      "graph_revision_id" => graph_revision_id,
      "correlation_id" => correlation_id,
      "simulation_params" => SimulationParams.to_params(simulation_params),
      "optimization_params" => OptimizationParams.to_params(optimization_params)
    }

    Workflows.start(@template, input, correlation_id: correlation_id)
  end

  def completed_event_payload(outputs) do
    %{
      baseline_experiment_id: get_in(outputs, [@baseline_step, "experiment_id"]),
      optimization_id: get_in(outputs, [@optimization_step, "optimization_run_id"]),
      output_graph_revision_id: get_in(outputs, [@optimization_step, "output_graph_revision_id"]),
      after_experiment_id: get_in(outputs, [@post_optimization_step, "experiment_id"])
    }
  end

  @impl true
  def steps, do: [@baseline_step, @optimization_step, @post_optimization_step]

  @impl true
  def prepare(_step, _input, _outputs, resource_id) when is_binary(resource_id),
    do: {:ok, resource_id}

  def prepare(@baseline_step, input, _outputs, nil) do
    prepare_simulation(input["graph_revision_id"], input)
  end

  def prepare(@optimization_step, input, _outputs, nil) do
    with {:ok, request} <- optimization_request(input),
         {:ok, run} <- Optimizations.prepare(request) do
      {:ok, run.id}
    end
  end

  def prepare(@post_optimization_step, input, outputs, nil) do
    case get_in(outputs, [@optimization_step, "output_graph_revision_id"]) do
      revision_id when is_binary(revision_id) ->
        prepare_simulation(revision_id, input)

      _ ->
        {:error, :missing_optimization_output}
    end
  end

  @impl true
  def run_or_resume(step, input, _outputs, resource_id)

  def run_or_resume(step, input, _outputs, resource_id)
      when step in [@baseline_step, @post_optimization_step] do
    with {:ok, experiment} <- Simulations.run_or_resume(resource_id, input["correlation_id"]) do
      {:ok,
       %{"experiment_id" => experiment.id, "graph_revision_id" => experiment.graph_revision_id}}
    end
  end

  def run_or_resume(@optimization_step, input, _outputs, resource_id) do
    with {:ok, request} <- optimization_request(input),
         {:ok, run} <- Optimizations.run_or_resume(resource_id, request) do
      {:ok,
       %{
         "optimization_run_id" => run.id,
         "output_graph_revision_id" => run.output_graph_revision_id
       }}
    end
  end

  defp simulation_params(input), do: SimulationParams.validate(input["simulation_params"])

  defp prepare_simulation(revision_id, input) do
    with {:ok, params} <- simulation_params(input),
         {:ok, experiment} <- Simulations.prepare(revision_id, params) do
      {:ok, experiment.id}
    end
  end

  defp optimization_request(input) do
    with {:ok, optimization_params} <- OptimizationParams.validate(input["optimization_params"]) do
      {:ok,
       %RunOptimizationRequest{
         graph_revision_id: input["graph_revision_id"],
         correlation_id: input["correlation_id"],
         optimization_params: optimization_params
       }}
    end
  end
end
