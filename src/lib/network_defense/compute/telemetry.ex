defmodule NetworkDefense.Compute.Telemetry do
  @moduledoc false

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias NetworkDefense.Observability

  @run_event [:network_defense, :scatter_gather, :run]
  @partition_event [:network_defense, :scatter_gather, :partition]

  @spec run(module(), map(), (integer() -> term())) :: term()
  def run(operation, metadata, fun) when is_function(fun, 1) do
    started_at = System.monotonic_time()
    metadata = metadata(operation, metadata)

    Tracer.with_span "scatter_gather.run", attributes: run_attributes(metadata) do
      Logger.debug(
        "Scatter-gather run started",
        log_metadata("scatter_gather.run.started", metadata)
      )

      execute_callback(:run, metadata, started_at, fn -> fun.(started_at) end)
    end
  end

  @spec partition(module(), term(), map(), (-> term())) :: term()
  def partition(operation, partition_key, metadata, fun) when is_function(fun, 0) do
    started_at = System.monotonic_time()
    metadata = metadata(operation, metadata) |> Map.put(:partition_key, inspect(partition_key))

    Tracer.with_span "scatter_gather.partition",
      attributes:
        Map.put(
          partition_attributes(metadata),
          "scatter_gather.partition.key",
          metadata.partition_key
        ) do
      execute_callback(:partition, metadata, started_at, fun)
    end
  end

  defp execute_callback(kind, metadata, started_at, fun) do
    try do
      result = fun.()
      outcome = outcome(result)

      Tracer.set_status(OpenTelemetry.status(if(outcome == "success", do: :ok, else: :error)))
      emit_duration(kind, started_at, Map.put(metadata, :outcome, outcome))
      log_result(kind, metadata, result, started_at)
      result
    rescue
      error ->
        stacktrace = __STACKTRACE__
        Tracer.record_exception(error, stacktrace)
        Tracer.set_status(OpenTelemetry.status(:error))
        emit_duration(kind, started_at, Map.put(metadata, :outcome, "error"))
        log_exception(kind, metadata, error, stacktrace, started_at)
        reraise error, stacktrace
    end
  end

  defp metadata(operation, %{correlation_id: correlation_id, executor: executor} = metadata) do
    %{
      correlation_id: correlation_id,
      executor: to_string(executor),
      operation: Atom.to_string(operation),
      partition_count: Map.get(metadata, :partition_count, 0)
    }
  end

  defp run_attributes(metadata) do
    Map.put(
      partition_attributes(metadata),
      "scatter_gather.partition_count",
      metadata.partition_count
    )
  end

  defp partition_attributes(metadata) do
    %{
      "network_defense.correlation.id" => metadata.correlation_id,
      "scatter_gather.operation" => metadata.operation,
      "scatter_gather.executor" => metadata.executor
    }
  end

  defp emit_duration(:run, started_at, metadata) do
    :telemetry.execute(
      @run_event,
      %{
        duration: System.monotonic_time() - started_at,
        partition_count: metadata.partition_count
      },
      metric_metadata(metadata)
    )
  end

  defp emit_duration(:partition, started_at, metadata) do
    Observability.emit_duration(@partition_event, started_at, metric_metadata(metadata))
  end

  defp metric_metadata(metadata), do: Map.take(metadata, [:operation, :executor, :outcome])

  defp outcome({:ok, _}), do: "success"
  defp outcome(_result), do: "error"

  defp log_result(:run, metadata, {:ok, _result}, started_at) do
    Logger.debug(
      "Scatter-gather run completed",
      log_metadata("scatter_gather.run.completed", metadata,
        runtime_ms: Observability.duration_ms(started_at)
      )
    )
  end

  defp log_result(:partition, _metadata, {:ok, _result}, _started_at), do: :ok

  defp log_result(kind, metadata, result, started_at) do
    Logger.error(
      "Scatter-gather #{kind} failed",
      log_metadata(
        "scatter_gather.#{kind}.failed",
        metadata,
        failure_log_fields(kind, metadata,
          runtime_ms: Observability.duration_ms(started_at),
          reason: result
        )
      )
    )
  end

  defp log_exception(kind, metadata, error, stacktrace, started_at) do
    Logger.error(
      Exception.format(:error, error, stacktrace),
      log_metadata(
        "scatter_gather.#{kind}.failed",
        metadata,
        failure_log_fields(kind, metadata, runtime_ms: Observability.duration_ms(started_at))
      )
    )
  end

  defp failure_log_fields(:partition, metadata, fields),
    do: Keyword.put(fields, :partition_key, metadata.partition_key)

  defp failure_log_fields(_kind, _metadata, fields), do: fields

  defp log_metadata(event, metadata, extra \\ []) do
    [
      event: event,
      correlation_id: metadata.correlation_id,
      operation: metadata.operation,
      executor: metadata.executor
    ] ++ extra
  end
end
