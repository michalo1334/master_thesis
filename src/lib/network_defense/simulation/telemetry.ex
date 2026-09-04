defmodule NetworkDefense.Simulation.Telemetry do
  @moduledoc false

  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Simulation.Experiment

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @simulator_run_event [:network_defense, :simulator, :run]

  @spec run(Experiment.t(), Graph.t(), String.t(), (-> term())) :: term()
  def run(experiment, graph, correlation_id, fun) when is_function(fun, 0) do
    Tracer.with_span "simulation.run",
      attributes: run_attributes(experiment, graph, correlation_id) do
      Logger.debug("Simulation started", run_log_metadata(experiment, graph, correlation_id))

      execute(
        fn result ->
          completed = completed_trials(result)
          Tracer.set_attributes(%{"simulation.completed_run_count": completed})

          Logger.debug(
            "Simulation completed",
            event: "simulation.run.completed",
            experiment_id: experiment.id,
            graph_id: graph.id,
            graph_revision_id: graph.revision_id,
            correlation_id: correlation_id,
            completed_run_count: completed,
            runtime_ms: runtime_ms(result)
          )
        end,
        fn error, stacktrace ->
          Logger.error(Exception.format(:error, error, stacktrace),
            correlation_id: correlation_id
          )
        end,
        fn reason ->
          Logger.error("Simulation failed", correlation_id: correlation_id, reason: reason)
        end,
        fun
      )
    end
  end

  @spec compute(Experiment.t(), Range.t() | [pos_integer()], (-> term())) :: term()
  def compute(_experiment, trial_indexes, fun) when is_function(fun, 0) do
    {first_trial_index, last_trial_index} = Enum.min_max(trial_indexes)

    Tracer.with_span "simulation.compute",
      attributes: %{
        "simulation.batch_size": Enum.count(trial_indexes),
        "simulation.first_trial_index": first_trial_index,
        "simulation.last_trial_index": last_trial_index
      } do
      try do
        {elapsed_us, _runs} = result = fun.()

        :telemetry.execute(
          @simulator_run_event,
          %{duration: System.convert_time_unit(elapsed_us, :microsecond, :native)},
          %{}
        )

        Tracer.set_status(OpenTelemetry.status(:ok))
        result
      rescue
        error ->
          stacktrace = __STACKTRACE__
          Tracer.record_exception(error, stacktrace)
          Tracer.set_status(OpenTelemetry.status(:error))
          reraise error, stacktrace
      end
    end
  end

  @spec report(Experiment.t(), (-> term())) :: term()
  def report(experiment, fun) when is_function(fun, 0) do
    Tracer.with_span "simulation.report.generate", attributes: report_attributes(experiment) do
      Logger.debug("Simulation report generation started", report_log_metadata(experiment))

      execute(
        fn report ->
          Logger.debug(
            "Simulation report generated",
            event: "report.simulation.completed",
            experiment_id: report.experiment_id,
            graph_id: report.graph_id,
            graph_revision_id: report.graph_revision_id,
            run_count: report.run_count,
            operational_flow_count: length(report.operational_flows)
          )
        end,
        fn _error, _stacktrace -> :ok end,
        fn _reason -> :ok end,
        fun
      )
    end
  end

  @spec enqueue_failed(String.t(), term()) :: :ok
  def enqueue_failed(correlation_id, reason) do
    Logger.error("Unable to enqueue simulation job: #{inspect(reason)}",
      correlation_id: correlation_id
    )
  end

  @spec batch_completed(
          String.t(),
          Experiment.t(),
          pos_integer(),
          pos_integer(),
          non_neg_integer()
        ) :: :ok
  def batch_completed(correlation_id, experiment, first_trial_index, last_trial_index, runtime_ms) do
    Logger.debug("Simulation batch completed",
      event: "simulation.batch.completed",
      correlation_id: correlation_id,
      experiment_id: experiment.id,
      completed_run_count: experiment.completed_trials,
      total_run_count: experiment.total_trials,
      first_trial_index: first_trial_index,
      last_trial_index: last_trial_index,
      runtime_ms: runtime_ms
    )
  end

  defp execute(on_success, on_exception, on_error, fun) do
    try do
      result = fun.()
      log_result(result, on_success, on_error)
      result
    rescue
      error ->
        stacktrace = __STACKTRACE__
        Tracer.record_exception(error, stacktrace)
        Tracer.set_status(OpenTelemetry.status(:error))
        on_exception.(error, stacktrace)
        reraise error, stacktrace
    end
  end

  defp log_result({:error, reason}, _on_success, on_error) do
    Tracer.set_status(OpenTelemetry.status(:error))
    on_error.(reason)
  end

  defp log_result(result, on_success, _on_error) do
    Tracer.set_status(OpenTelemetry.status(:ok))
    on_success.(result)
  end

  defp run_attributes(experiment, graph, correlation_id) do
    %{
      "graph.id": graph.id,
      "graph.revision_id": graph.revision_id,
      "simulation.experiment_id": experiment.id,
      "network_defense.correlation.id": correlation_id,
      "simulation.run_count": experiment.total_trials,
      "simulation.iteration_count": experiment.iteration_count,
      "simulation.max_attempts": experiment.max_attempts
    }
  end

  defp report_attributes(experiment) do
    %{
      "simulation.experiment_id": experiment.id,
      "graph.id": experiment.graph.id,
      "graph.revision_id": experiment.graph_revision_id,
      "simulation.run_count": length(experiment.runs),
      "simulation.iteration_count": experiment.iteration_count
    }
  end

  defp run_log_metadata(experiment, graph, correlation_id) do
    [
      event: "simulation.run.started",
      experiment_id: experiment.id,
      graph_id: graph.id,
      graph_revision_id: graph.revision_id,
      correlation_id: correlation_id,
      run_count: experiment.total_trials,
      iteration_count: experiment.iteration_count
    ]
  end

  defp report_log_metadata(experiment) do
    [
      event: "report.simulation.started",
      experiment_id: experiment.id,
      graph_id: experiment.graph.id,
      graph_revision_id: experiment.graph_revision_id,
      run_count: length(experiment.runs),
      iteration_count: experiment.iteration_count
    ]
  end

  defp completed_trials(%{completed_trials: completed_trials}), do: completed_trials
  defp completed_trials(_result), do: 0

  defp runtime_ms(%{runtime_ms: runtime_ms}), do: runtime_ms
  defp runtime_ms(_result), do: 0
end
