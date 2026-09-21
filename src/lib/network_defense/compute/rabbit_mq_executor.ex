defmodule NetworkDefense.Compute.RabbitMQExecutor do
  @moduledoc false

  @behaviour NetworkDefense.Compute.ScatterGather.Executor

  alias NetworkDefense.Compute.{
    RabbitMQ.Connection,
    RabbitMQ.Envelope,
    RabbitMQ.Worker,
    Telemetry
  }

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
      with {:ok, operation_name} <- operation_name(operation) do
        run_partitions(partitions, operation, operation_name, input, metadata, started_at, opts)
      end
    end)
  end

  defp run_partitions([], operation, _operation_name, input, _metadata, started_at, _opts),
    do: gather(operation, [], input, started_at)

  defp run_partitions(partitions, operation, operation_name, input, metadata, started_at, opts) do
    with {:ok, channel} <- Connection.open_channel() do
      monitor = Process.monitor(channel.pid)
      context = %{operation: operation, input: input, started_at: started_at, monitor: monitor}

      try do
        run_with_channel(channel, partitions, context, operation_name, metadata, opts)
      after
        Process.demonitor(monitor, [:flush])
        close_channel(channel)
      end
    end
  end

  defp run_with_channel(channel, partitions, context, operation_name, metadata, opts) do
    with :ok <- AMQP.Confirm.select(channel),
         {:ok, %{queue: reply_queue}} <-
           AMQP.Queue.declare(channel, "", exclusive: true, auto_delete: true) do
      try do
        case AMQP.Basic.consume(channel, reply_queue, self(), no_ack: true) do
          {:ok, _consumer_tag} ->
            state = initial_state(partitions, operation_name, metadata, opts, reply_queue)

            with {:ok, state} <- publish_window(channel, state),
                 do: collect(channel, context, state)

          _result ->
            {:error, :channel_setup_failed}
        end
      after
        delete_queue(channel, reply_queue)
      end
    else
      _result -> {:error, :channel_setup_failed}
    end
  catch
    :exit, _reason -> {:error, :channel_setup_failed}
  end

  defp initial_state(partitions, operation_name, metadata, opts, reply_queue) do
    %{
      pending:
        Enum.map(partitions, fn {key, work_units, partition} ->
          %{id: identifier(), key: key, work_units: work_units, partition: partition}
        end),
      in_flight: %{},
      results: [],
      completed: 0,
      total: Enum.sum_by(partitions, &elem(&1, 1)),
      max_concurrency: max(1, Keyword.get(opts, :max_concurrency, System.schedulers_online())),
      on_progress: Keyword.get(opts, :on_progress, fn _progress -> :ok end),
      run_id: identifier(),
      operation: operation_name,
      correlation_id: metadata.correlation_id,
      reply_queue: reply_queue
    }
  end

  defp publish_window(channel, %{pending: [partition | pending], in_flight: in_flight} = state)
       when map_size(in_flight) < state.max_concurrency do
    work = %{
      version: 1,
      run_id: state.run_id,
      partition_id: partition.id,
      partition_key: partition.key,
      work_units: partition.work_units,
      operation: state.operation,
      partition: partition.partition,
      trace_headers: [] |> :otel_propagator_text_map.inject() |> Map.new()
    }

    with {:ok, payload} <- Envelope.encode_work(work),
         :ok <- Telemetry.message_payload("work", byte_size(payload)),
         :ok <-
           AMQP.Basic.publish(channel, "", Worker.work_queue(), payload,
             reply_to: state.reply_queue,
             correlation_id: state.correlation_id,
             delivery_mode: 1,
             expiration: Integer.to_string(result_timeout())
           ),
         true <- AMQP.Confirm.wait_for_confirms(channel) do
      publish_window(channel, %{
        state
        | pending: pending,
          in_flight: Map.put(in_flight, partition.id, partition)
      })
    else
      _result -> {:error, :work_publication_failed}
    end
  catch
    :exit, _reason -> {:error, :work_publication_failed}
  end

  defp publish_window(_channel, state), do: {:ok, state}

  defp collect(channel, context, state) do
    receive_result(channel, context, state, deadline())
  end

  defp receive_result(channel, %{monitor: monitor} = context, state, deadline) do
    receive do
      {:cancel_simulation, _experiment_id} ->
        {:error, :cancelled}

      {:basic_cancel, _meta} ->
        {:error, :consumer_cancelled}

      {:DOWN, ^monitor, :process, _pid, _reason} ->
        {:error, :channel_closed}

      {:basic_deliver, payload, _meta} ->
        case Envelope.decode_result(payload) do
          {:ok, %{run_id: run_id, partition_id: partition_id, outcome: outcome}}
          when run_id == state.run_id ->
            handle_result(
              channel,
              context,
              state,
              partition_id,
              outcome,
              deadline
            )

          _result ->
            receive_result(channel, context, state, deadline)
        end
    after
      remaining_timeout(deadline) -> {:error, :result_timeout}
    end
  end

  defp handle_result(channel, context, state, partition_id, outcome, deadline) do
    case Map.pop(state.in_flight, partition_id) do
      {nil, _in_flight} ->
        receive_result(channel, context, state, deadline)

      {partition, in_flight} ->
        handle_outcome(channel, context, state, partition, in_flight, outcome)
    end
  end

  defp handle_outcome(_channel, _context, _state, _partition, _in_flight, {:error, reason}),
    do: {:error, reason}

  defp handle_outcome(
         channel,
         context,
         state,
         %{key: key, work_units: work_units},
         in_flight,
         {:ok, result}
       ) do
    completed = state.completed + work_units

    with :ok <- report_progress(state.on_progress, %{completed: completed, total: state.total}),
         {:ok, state} <-
           publish_window(channel, %{
             state
             | in_flight: in_flight,
               completed: completed,
               results: [{key, result} | state.results]
           }) do
      continue_or_gather(channel, context, state)
    end
  end

  defp continue_or_gather(
         _channel,
         %{operation: operation, input: input, started_at: started_at},
         state
       )
       when map_size(state.in_flight) == 0 do
    gather(operation, state.results, input, started_at)
  end

  defp continue_or_gather(channel, context, state) do
    receive_result(channel, context, state, deadline())
  end

  defp gather(operation, results, input, started_at) do
    operation.gather(results, input, %{
      compute_duration_ms: NetworkDefense.Observability.duration_ms(started_at)
    })
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

  defp operation_name(NetworkDefense.Simulation.SimulationOperation), do: {:ok, "simulation"}
  defp operation_name(_operation), do: {:error, :unsupported_operation}

  defp deadline do
    System.monotonic_time(:millisecond) + result_timeout()
  end

  defp remaining_timeout(deadline), do: max(0, deadline - System.monotonic_time(:millisecond))

  defp result_timeout do
    :network_defense
    |> Application.fetch_env!(:rabbitmq)
    |> Keyword.fetch!(:result_inactivity_timeout_ms)
  end

  defp identifier, do: :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)

  defp delete_queue(channel, queue) do
    AMQP.Queue.delete(channel, queue)
  catch
    :exit, _reason -> :ok
  end

  defp close_channel(channel) do
    AMQP.Channel.close(channel)
  catch
    :exit, _reason -> :ok
  end
end
