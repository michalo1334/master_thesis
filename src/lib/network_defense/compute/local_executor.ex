defmodule NetworkDefense.Compute.LocalExecutor do
  @moduledoc false

  @behaviour NetworkDefense.Compute.ScatterGather.Executor

  alias NetworkDefense.Compute.Telemetry

  @impl true
  @spec run(module(), term(), keyword()) :: {:ok, term()} | {:error, term()}
  def run(operation, input, opts) do
    partitions = Enum.to_list(operation.scatter(input))

    metadata = %{
      correlation_id: Keyword.fetch!(opts, :correlation_id),
      executor: __MODULE__,
      partition_count: length(partitions)
    }

    Telemetry.run(operation, metadata, fn started_at ->
      case execute_partitions(partitions, operation, metadata, opts) do
        {:ok, results} ->
          operation.gather(results, input, %{
            compute_duration_ms: NetworkDefense.Observability.duration_ms(started_at)
          })

        {:error, _reason} = error ->
          error
      end
    end)
  end

  defp execute_partitions(partitions, operation, metadata, opts) do
    total = Enum.sum_by(partitions, &elem(&1, 1))
    on_progress = Keyword.get(opts, :on_progress, fn _progress -> :ok end)

    OpentelemetryProcessPropagator.Task.Supervisor.async_stream_nolink(
      NetworkDefense.TaskSupervisor,
      partitions,
      fn {key, work_units, partition} ->
        {key, work_units, execute_partition(operation, key, partition, metadata)}
      end,
      ordered: false,
      timeout: :infinity,
      max_concurrency: Keyword.get(opts, :max_concurrency, System.schedulers_online())
    )
    |> Enum.reduce_while({:ok, [], 0}, fn
      {:ok, {key, work_units, {:ok, result}}}, {:ok, results, completed} ->
        completed = completed + work_units

        case report_progress(on_progress, %{completed: completed, total: total}) do
          :ok -> {:cont, {:ok, [{key, result} | results], completed}}
          {:error, _reason} = error -> {:halt, error}
        end

      {:ok, {_key, _work_units, {:error, reason}}}, _state ->
        {:halt, {:error, reason}}

      {:exit, reason}, _state ->
        {:halt, {:error, reason}}
    end)
    |> case do
      {:ok, results, _completed} -> {:ok, Enum.reverse(results)}
      {:error, _reason} = error -> error
    end
  end

  defp execute_partition(operation, key, partition, metadata) do
    Telemetry.partition(operation, key, metadata, fn -> operation.execute(fn -> partition end) end)
  end

  defp report_progress(on_progress, progress) do
    case on_progress.(progress) do
      {:error, _reason} = error -> error
      _result -> :ok
    end
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end
end
