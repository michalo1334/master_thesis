defmodule NetworkDefense.Compute.RabbitMQ.Worker do
  @moduledoc false

  use GenServer

  alias NetworkDefense.Compute.{RabbitMQ.Connection, RabbitMQ.Envelope, Telemetry}

  @reconnect_delay_ms 1_000
  @work_queue "network_defense.compute.work"

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @spec work_queue() :: String.t()
  def work_queue, do: @work_queue

  @impl true
  def init(:ok) do
    send(self(), :open_channel)
    {:ok, %{channel: nil, monitor: nil}}
  end

  @impl true
  def handle_info(:open_channel, %{channel: nil} = state) do
    case open_channel() do
      {:ok, channel} ->
        {:noreply, %{state | channel: channel, monitor: Process.monitor(channel.pid)}}

      {:error, _reason} ->
        schedule_open_channel()
        {:noreply, state}
    end
  end

  def handle_info(:open_channel, state), do: {:noreply, state}

  def handle_info({:basic_deliver, payload, meta}, %{channel: channel} = state)
      when not is_nil(channel) do
    case process_delivery(channel, payload, meta) do
      :ok -> {:noreply, state}
      :close_channel -> {:noreply, close_and_recover(state)}
    end
  end

  def handle_info({:basic_cancel, _meta}, state), do: {:noreply, close_and_recover(state)}

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{monitor: monitor} = state) do
    schedule_open_channel()
    {:noreply, %{state | channel: nil, monitor: nil}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp open_channel do
    with {:ok, channel} <- Connection.open_channel() do
      case configure_channel(channel) do
        :ok ->
          {:ok, channel}

        {:error, _reason} = error ->
          close_channel(channel)
          error
      end
    end
  end

  defp configure_channel(channel) do
    with {:ok, _queue} <- AMQP.Queue.declare(channel, @work_queue, durable: true),
         :ok <- AMQP.Basic.qos(channel, prefetch_count: 1),
         :ok <- AMQP.Confirm.select(channel),
         {:ok, _consumer_tag} <- AMQP.Basic.consume(channel, @work_queue, self(), no_ack: false) do
      :ok
    end
  catch
    :exit, _reason -> {:error, :channel_setup_failed}
  end

  defp process_delivery(channel, payload, meta) do
    case Envelope.decode_work(payload) do
      {:ok, envelope} when is_binary(meta.reply_to) and byte_size(meta.reply_to) > 0 ->
        process_work(channel, payload, envelope, meta)

      {:ok, _envelope} ->
        acknowledge(channel, meta.delivery_tag)

      {:error, _reason} ->
        acknowledge(channel, meta.delivery_tag)
    end
  end

  defp process_work(channel, payload, envelope, meta) do
    if Map.get(meta, :redelivered, false), do: Telemetry.redelivered_partition()

    outcome = execute(envelope, meta, byte_size(payload))

    case publish_result(channel, envelope, outcome, meta) do
      :ok -> acknowledge(channel, meta.delivery_tag)
      {:error, _reason} -> :close_channel
    end
  end

  defp execute(envelope, meta, work_payload_bytes) do
    context_token =
      envelope.trace_headers
      |> Map.to_list()
      |> :otel_propagator_text_map.extract()

    try do
      NetworkDefense.TaskSupervisor
      |> OpentelemetryProcessPropagator.Task.Supervisor.async_nolink(fn ->
        Telemetry.partition(
          envelope.operation_module,
          envelope.partition_key,
          telemetry_metadata(meta, work_payload_bytes),
          fn ->
            envelope.operation_module.execute(fn -> envelope.partition end)
          end
        )
      end)
      |> Task.await(:infinity)
      |> terminal_outcome()
    catch
      :exit, reason -> {:error, compact_error({:task_exit, reason})}
    after
      OpenTelemetry.Ctx.detach(context_token)
    end
  end

  defp terminal_outcome({:ok, _result} = outcome), do: outcome
  defp terminal_outcome({:error, reason}), do: {:error, compact_error(reason)}
  defp terminal_outcome(result), do: {:error, compact_error({:invalid_task_result, result})}

  defp publish_result(channel, envelope, outcome, meta) do
    result = %{
      version: 1,
      run_id: envelope.run_id,
      partition_id: envelope.partition_id,
      partition_key: envelope.partition_key,
      outcome: outcome
    }

    with {:ok, payload} <- encode_result(result),
         :ok <- Telemetry.message_payload("result", byte_size(payload)),
         reply_to when is_binary(reply_to) and byte_size(reply_to) > 0 <- meta.reply_to,
         :ok <-
           AMQP.Basic.publish(channel, "", reply_to, payload, correlation_id: meta.correlation_id),
         true <- AMQP.Confirm.wait_for_confirms(channel) do
      :ok
    else
      _result -> {:error, :result_publication_failed}
    end
  catch
    :exit, _reason -> {:error, :result_publication_failed}
  end

  defp encode_result(result) do
    case Envelope.encode_result(result) do
      {:ok, _payload} = encoded ->
        encoded

      {:error, :payload_too_large} ->
        Envelope.encode_result(%{result | outcome: {:error, "result_too_large"}})

      {:error, _reason} = error ->
        error
    end
  end

  defp acknowledge(channel, delivery_tag) do
    case AMQP.Basic.ack(channel, delivery_tag) do
      :ok -> :ok
      {:error, _reason} -> :close_channel
    end
  catch
    :exit, _reason -> :close_channel
  end

  defp telemetry_metadata(meta, work_payload_bytes) do
    %{
      correlation_id: Map.get(meta, :correlation_id) || "rabbitmq",
      executor: __MODULE__,
      redelivered: Map.get(meta, :redelivered, false),
      work_payload_bytes: work_payload_bytes
    }
  end

  defp compact_error(reason), do: inspect(reason, limit: 20, printable_limit: 500)

  defp close_and_recover(%{channel: nil} = state) do
    schedule_open_channel()
    state
  end

  defp close_and_recover(%{channel: channel, monitor: monitor} = state) do
    Process.demonitor(monitor, [:flush])
    close_channel(channel)
    schedule_open_channel()
    %{state | channel: nil, monitor: nil}
  end

  defp close_channel(channel) do
    AMQP.Channel.close(channel)
  catch
    :exit, _reason -> :ok
  end

  defp schedule_open_channel, do: Process.send_after(self(), :open_channel, @reconnect_delay_ms)
end
