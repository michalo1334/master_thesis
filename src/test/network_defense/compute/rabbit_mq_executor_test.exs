defmodule NetworkDefense.Compute.RabbitMQExecutorTest do
  use ExUnit.Case, async: false

  alias NetworkDefense.Compute.RabbitMQ.Envelope
  alias NetworkDefense.Compute.RabbitMQExecutor

  setup do
    parent = self()

    modules = [
      AMQP.Basic,
      AMQP.Channel,
      AMQP.Confirm,
      AMQP.Queue,
      NetworkDefense.Compute.RabbitMQ.Connection,
      NetworkDefense.Simulation.SimulationOperation
    ]

    for module <- modules, do: :meck.new(module, [:passthrough])
    on_exit(fn -> Enum.each(modules, &safe_unload/1) end)

    :meck.expect(NetworkDefense.Compute.RabbitMQ.Connection, :open_channel, fn ->
      {:ok, %AMQP.Channel{pid: parent}}
    end)

    :meck.expect(AMQP.Confirm, :select, fn _channel -> :ok end)
    :meck.expect(AMQP.Confirm, :wait_for_confirms, fn _channel -> true end)

    :meck.expect(AMQP.Queue, :declare, fn _channel, "", options ->
      send(parent, {:reply_queue, options})
      {:ok, %{queue: "reply"}}
    end)

    :meck.expect(AMQP.Queue, :delete, fn _channel, "reply" ->
      send(parent, :reply_queue_deleted)
      :ok
    end)

    :meck.expect(AMQP.Channel, :close, fn _channel ->
      send(parent, :channel_closed)
      :ok
    end)

    :meck.expect(AMQP.Basic, :consume, fn _channel, "reply", pid, [no_ack: true] ->
      send(parent, {:reply_consumer, pid})
      {:ok, "consumer"}
    end)

    :ok
  end

  test "gathers keyed unordered results, limits publications, and reports unique weighted progress" do
    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :scatter, fn input ->
      input.partitions
    end)

    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :gather, fn results,
                                                                            _input,
                                                                            _stats ->
      send(self(), {:gathered, results})
      {:ok, :done}
    end)

    :meck.expect(AMQP.Basic, :publish, fn _channel, "", _queue, payload, _options ->
      {:ok, work} = Envelope.decode_work(payload)

      {:ok, result} =
        work
        |> Map.take([:version, :run_id, :partition_id, :partition_key])
        |> Map.put(:outcome, {:ok, work.partition})
        |> Envelope.encode_result()

      send(self(), {:basic_deliver, result, %{}})
      send(self(), {:basic_deliver, result, %{}})
      :ok
    end)

    progress = fn update -> send(self(), {:progress, update}) end

    assert {:ok, :done} =
             RabbitMQExecutor.run(NetworkDefense.Simulation.SimulationOperation, input(),
               correlation_id: "executor",
               max_concurrency: 1,
               on_progress: progress
             )

    assert_received {:reply_queue, [exclusive: true, auto_delete: true]}
    assert_received {:gathered, results}
    assert Enum.sort(results) == [{:first, :first}, {:second, :second}]
    assert_received {:progress, %{completed: 2, total: 5}}
    assert_received {:progress, %{completed: 5, total: 5}}
    refute_received {:progress, _progress}
    assert_received :reply_queue_deleted
    assert_received :channel_closed
  end

  test "emits work payload telemetry with only its fixed label" do
    attach_telemetry_handler()

    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :scatter, fn input ->
      input.partitions
    end)

    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :gather, fn _results,
                                                                            _input,
                                                                            _stats ->
      {:ok, :done}
    end)

    :meck.expect(AMQP.Basic, :publish, fn _channel, "", _queue, payload, _options ->
      {:ok, work} = Envelope.decode_work(payload)

      {:ok, result} =
        work
        |> Map.take([:version, :run_id, :partition_id, :partition_key])
        |> Map.put(:outcome, {:ok, :done})
        |> Envelope.encode_result()

      send(self(), {:basic_deliver, result, %{}})
      :ok
    end)

    assert {:ok, :done} =
             RabbitMQExecutor.run(
               NetworkDefense.Simulation.SimulationOperation,
               input([{:key_not_a_label, 1, :partition}]),
               correlation_id: "not-a-metric-label"
             )

    assert_receive {:telemetry, [:network_defense, :rabbitmq, :message], %{payload_size: bytes},
                    metadata}

    assert bytes > 0
    assert metadata == %{direction: "work"}
  end

  test "returns a partition error without gathering" do
    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :scatter, fn input ->
      input.partitions
    end)

    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :gather, fn _results,
                                                                            _input,
                                                                            _stats ->
      flunk("gathered")
    end)

    :meck.expect(AMQP.Basic, :publish, fn _channel, "", _queue, payload, _options ->
      {:ok, work} = Envelope.decode_work(payload)

      {:ok, result} =
        work
        |> Map.take([:version, :run_id, :partition_id, :partition_key])
        |> Map.put(:outcome, {:error, :failed})
        |> Envelope.encode_result()

      send(self(), {:basic_deliver, result, %{}})
      :ok
    end)

    assert {:error, :failed} =
             RabbitMQExecutor.run(
               NetworkDefense.Simulation.SimulationOperation,
               input([{:first, 1, :first}]),
               correlation_id: "executor-error"
             )
  end

  test "stops on progress errors without gathering" do
    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :scatter, fn input ->
      input.partitions
    end)

    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :gather, fn _, _, _ ->
      flunk("gathered")
    end)

    :meck.expect(AMQP.Basic, :publish, fn _channel, "", _queue, payload, _options ->
      {:ok, work} = Envelope.decode_work(payload)

      {:ok, result} =
        work
        |> Map.take([:version, :run_id, :partition_id, :partition_key])
        |> Map.put(:outcome, {:ok, :done})
        |> Envelope.encode_result()

      send(self(), {:basic_deliver, result, %{}})
      :ok
    end)

    assert {:error, :progress_failed} =
             RabbitMQExecutor.run(
               NetworkDefense.Simulation.SimulationOperation,
               input([{:first, 1, :first}]),
               correlation_id: "executor-progress-error",
               on_progress: fn _ -> {:error, :progress_failed} end
             )
  end

  test "gathers an empty scatter without publishing work" do
    :meck.expect(NetworkDefense.Compute.RabbitMQ.Connection, :open_channel, fn ->
      flunk("opened a channel")
    end)

    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :scatter, fn _input -> [] end)

    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :gather, fn results,
                                                                            _input,
                                                                            _stats ->
      send(self(), {:gathered, results})
      {:ok, :done}
    end)

    assert {:ok, :done} =
             RabbitMQExecutor.run(NetworkDefense.Simulation.SimulationOperation, %{},
               correlation_id: "executor-empty"
             )

    assert_received {:gathered, []}
  end

  test "ignores results for another run" do
    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :scatter, fn input ->
      input.partitions
    end)

    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :gather, fn results, _, _ ->
      send(self(), {:gathered, results})
      {:ok, :done}
    end)

    :meck.expect(AMQP.Basic, :publish, fn _channel, "", _queue, payload, _options ->
      {:ok, work} = Envelope.decode_work(payload)

      {:ok, result} =
        work
        |> Map.take([:version, :run_id, :partition_id, :partition_key])
        |> Map.put(:outcome, {:ok, :done})
        |> Envelope.encode_result()

      {:ok, wrong_run_result} =
        work
        |> Map.take([:version, :partition_id, :partition_key])
        |> Map.merge(%{run_id: "another-run", outcome: {:ok, :wrong}})
        |> Envelope.encode_result()

      send(self(), {:basic_deliver, wrong_run_result, %{}})
      send(self(), {:basic_deliver, result, %{}})
      :ok
    end)

    assert {:ok, :done} =
             RabbitMQExecutor.run(
               NetworkDefense.Simulation.SimulationOperation,
               input([{:first, 1, :first}]),
               correlation_id: "executor-other-run"
             )

    assert_received {:gathered, [{:first, :done}]}
  end

  test "cancels and cleans up the reply queue and channel" do
    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :scatter, fn input ->
      input.partitions
    end)

    :meck.expect(AMQP.Basic, :publish, fn _channel, "", _queue, _payload, _options ->
      send(self(), {:cancel_simulation, "experiment"})
      :ok
    end)

    assert {:error, :cancelled} =
             RabbitMQExecutor.run(
               NetworkDefense.Simulation.SimulationOperation,
               input([{:first, 1, :first}]),
               correlation_id: "executor-cancelled"
             )

    assert_received :reply_queue_deleted
    assert_received :channel_closed
  end

  test "deletes the reply queue when consumer setup fails" do
    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :scatter, fn input ->
      input.partitions
    end)

    :meck.expect(AMQP.Basic, :consume, fn _channel, "reply", _pid, [no_ack: true] ->
      {:error, :closed}
    end)

    assert {:error, :channel_setup_failed} =
             RabbitMQExecutor.run(
               NetworkDefense.Simulation.SimulationOperation,
               input([{:first, 1, :first}]),
               correlation_id: "executor-consumer-failure"
             )

    assert_received :reply_queue_deleted
  end

  test "returns channel closed when the channel process exits" do
    :meck.expect(NetworkDefense.Compute.RabbitMQ.Connection, :open_channel, fn ->
      pid = spawn(fn -> Process.sleep(:infinity) end)
      {:ok, %AMQP.Channel{pid: pid}}
    end)

    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :scatter, fn input ->
      input.partitions
    end)

    :meck.expect(AMQP.Basic, :publish, fn %AMQP.Channel{pid: pid},
                                          "",
                                          _queue,
                                          _payload,
                                          _options ->
      Process.exit(pid, :kill)
      :ok
    end)

    assert {:error, :channel_closed} =
             RabbitMQExecutor.run(
               NetworkDefense.Simulation.SimulationOperation,
               input([{:first, 1, :first}]),
               correlation_id: "executor-channel-closed"
             )
  end

  test "returns result timeout only when an expected result remains silent" do
    previous_timeout = Application.fetch_env!(:network_defense, :rabbitmq)

    Application.put_env(
      :network_defense,
      :rabbitmq,
      Keyword.put(previous_timeout, :result_inactivity_timeout_ms, 1)
    )

    on_exit(fn -> Application.put_env(:network_defense, :rabbitmq, previous_timeout) end)

    :meck.expect(NetworkDefense.Simulation.SimulationOperation, :scatter, fn input ->
      input.partitions
    end)

    :meck.expect(AMQP.Basic, :publish, fn _channel, "", _queue, _payload, _options -> :ok end)

    assert {:error, :result_timeout} =
             RabbitMQExecutor.run(
               NetworkDefense.Simulation.SimulationOperation,
               input([{:first, 1, :first}]),
               correlation_id: "executor-timeout"
             )
  end

  defp input(partitions \\ [{:first, 2, :first}, {:second, 3, :second}]),
    do: %{partitions: partitions}

  defp attach_telemetry_handler do
    handler = "executor-telemetry-#{System.unique_integer([:positive])}"
    parent = self()

    :telemetry.attach(
      handler,
      [:network_defense, :rabbitmq, :message],
      fn event, measurements, metadata, _config ->
        send(parent, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  defp safe_unload(module) do
    :meck.unload(module)
  catch
    :error, {:not_mocked, _module} -> :ok
  end
end
