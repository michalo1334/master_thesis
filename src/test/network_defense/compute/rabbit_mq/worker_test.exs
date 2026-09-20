defmodule NetworkDefense.Compute.RabbitMQ.WorkerTest do
  use ExUnit.Case, async: false

  alias NetworkDefense.Compute.RabbitMQ.{Envelope, Worker}

  setup do
    parent = self()

    modules = [
      AMQP.Basic,
      AMQP.Channel,
      AMQP.Confirm,
      AMQP.Queue,
      NetworkDefense.Compute.RabbitMQ.Connection,
      NetworkDefense.Simulation.SimulationOperation,
      :otel_propagator_text_map
    ]

    for module <- modules do
      :meck.new(module, [:passthrough])
    end

    on_exit(fn -> Enum.each(modules, &safe_unload/1) end)

    :meck.expect(AMQP.Basic, :ack, fn _channel, delivery_tag ->
      send(parent, {:ack, delivery_tag})
      :ok
    end)

    :meck.expect(AMQP.Basic, :publish, fn _channel, _exchange, _queue, payload, _options ->
      send(parent, {:published, payload})
      :ok
    end)

    :meck.expect(AMQP.Confirm, :wait_for_confirms, fn _channel -> true end)

    :meck.expect(:otel_propagator_text_map, :extract, fn carrier ->
      send(parent, {:trace_carrier, carrier})
      :meck.passthrough([carrier])
    end)

    :meck.expect(AMQP.Channel, :close, fn _channel ->
      send(parent, :channel_closed)
      :ok
    end)

    :ok
  end

  test "acknowledges successful work after its confirmed result" do
    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :execute, fn _fetch ->
      {:ok, :done}
    end)

    assert {:noreply, _state} = deliver(work_payload(), delivery_meta())
    assert_received {:published, _payload}
    assert_received {:ack, 7}
  end

  test "publishes tagged errors before acknowledgement" do
    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :execute, fn _fetch ->
      {:error, :failed}
    end)

    assert {:noreply, _state} = deliver(work_payload(), delivery_meta())
    assert_received {:published, payload}
    assert_received {:ack, 7}
    assert {:ok, %{outcome: {:error, reason}}} = Envelope.decode_result(payload)
    assert is_binary(reason)
  end

  test "publishes task exits as terminal errors" do
    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :execute, fn _fetch ->
      exit(:failed)
    end)

    assert {:noreply, _state} = deliver(work_payload(), delivery_meta())
    assert_received {:published, payload}
    assert_received {:ack, 7}
    assert {:ok, %{outcome: {:error, reason}}} = Envelope.decode_result(payload)
    assert reason =~ "task_exit"
  end

  test "extracts trace context from a text-map carrier" do
    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :execute, fn _fetch ->
      {:ok, :done}
    end)

    assert {:noreply, _state} =
             deliver(work_payload(%{"traceparent" => "00-trace"}), delivery_meta())

    assert_received {:trace_carrier, [{"traceparent", "00-trace"}]}
  end

  test "acknowledges malformed work without publishing" do
    assert {:noreply, _state} = deliver("invalid", delivery_meta())
    assert_received {:ack, 7}
    refute_received {:published, _payload}
  end

  test "acknowledges valid work with no reply queue without executing it" do
    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :execute, fn _fetch ->
      flunk("executed")
    end)

    assert {:noreply, _state} = deliver(work_payload(), %{delivery_meta() | reply_to: nil})
    assert_received {:ack, 7}
    refute_received {:published, _payload}
  end

  test "closes its channel without acknowledgement when result publication fails" do
    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :execute, fn _fetch ->
      {:ok, :done}
    end)

    :meck.expect(AMQP.Basic, :publish, fn _channel, _exchange, _queue, _payload, _options ->
      {:error, :closed}
    end)

    assert {:noreply, %{channel: nil}} = deliver(work_payload(), delivery_meta())
    assert_received :channel_closed
    refute_received {:ack, 7}
  end

  test "closes its channel without acknowledgement when result confirmation fails" do
    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :execute, fn _fetch ->
      {:ok, :done}
    end)

    :meck.expect(AMQP.Confirm, :wait_for_confirms, fn _channel -> false end)

    assert {:noreply, %{channel: nil}} = deliver(work_payload(), delivery_meta())
    assert_received :channel_closed
    refute_received {:ack, 7}
  end

  test "reopens after a monitored channel exits" do
    monitor = Process.monitor(self())
    state = %{channel: :channel, monitor: monitor}

    assert {:noreply, %{channel: nil, monitor: nil}} =
             Worker.handle_info({:DOWN, monitor, :process, self(), :closed}, state)
  end

  test "declares a durable queue and consumes one unacknowledged message at a time" do
    channel = %AMQP.Channel{pid: self()}
    parent = self()

    :meck.expect(NetworkDefense.Compute.RabbitMQ.Connection, :open_channel, fn ->
      {:ok, channel}
    end)

    :meck.expect(AMQP.Queue, :declare, fn ^channel, queue, options ->
      send(parent, {:declare, queue, options})
      {:ok, %{queue: queue}}
    end)

    :meck.expect(AMQP.Basic, :qos, fn ^channel, options ->
      send(parent, {:qos, options})
      :ok
    end)

    :meck.expect(AMQP.Confirm, :select, fn ^channel -> :ok end)

    :meck.expect(AMQP.Basic, :consume, fn ^channel, queue, pid, options ->
      send(parent, {:consume, queue, pid, options})
      {:ok, "consumer"}
    end)

    assert {:noreply, %{channel: ^channel}} =
             Worker.handle_info(:open_channel, %{channel: nil, monitor: nil})

    assert_received {:declare, "network_defense.compute.work", [durable: true]}
    assert_received {:qos, [prefetch_count: 1]}
    assert_received {:consume, "network_defense.compute.work", _pid, [no_ack: false]}
  end

  test "closes a new channel when consumer setup fails" do
    channel = %AMQP.Channel{pid: self()}

    :meck.expect(NetworkDefense.Compute.RabbitMQ.Connection, :open_channel, fn ->
      {:ok, channel}
    end)

    :meck.expect(AMQP.Queue, :declare, fn ^channel, _queue, _options ->
      {:error, :closed}
    end)

    assert {:noreply, %{channel: nil}} =
             Worker.handle_info(:open_channel, %{channel: nil, monitor: nil})

    assert_received :channel_closed
  end

  defp deliver(payload, meta) do
    Worker.handle_info({:basic_deliver, payload, meta}, %{channel: :channel, monitor: make_ref()})
  end

  defp work_payload(trace_headers \\ %{}) do
    {:ok, payload} =
      Envelope.encode_work(%{
        version: 1,
        run_id: "run",
        partition_id: "partition",
        partition_key: :key,
        work_units: 1,
        operation: "simulation",
        partition: :partition,
        trace_headers: trace_headers
      })

    payload
  end

  defp delivery_meta do
    %{delivery_tag: 7, reply_to: "reply", correlation_id: "correlation"}
  end

  defp safe_unload(module) do
    :meck.unload(module)
  catch
    :error, {:not_mocked, _module} -> :ok
  end
end
