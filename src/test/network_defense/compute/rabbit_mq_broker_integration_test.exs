defmodule NetworkDefense.Compute.RabbitMQBrokerIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :rabbitmq
  @moduletag timeout: 15_000

  test "independently connected consumers are both eligible for shared-queue work" do
    queue = "network_defense.integration.#{System.unique_integer([:positive])}"
    {:ok, publisher_connection} = AMQP.Connection.open(broker_config())
    {:ok, publisher_channel} = AMQP.Channel.open(publisher_connection)
    {:ok, consumer_one_connection} = AMQP.Connection.open(broker_config())
    {:ok, consumer_one_channel} = AMQP.Channel.open(consumer_one_connection)
    {:ok, consumer_two_connection} = AMQP.Connection.open(broker_config())
    {:ok, consumer_two_channel} = AMQP.Channel.open(consumer_two_connection)

    on_exit(fn ->
      close_channel(consumer_two_channel)
      close_connection(consumer_two_connection)
      close_channel(consumer_one_channel)
      close_connection(consumer_one_connection)
      delete_queue(publisher_channel, queue)
      close_channel(publisher_channel)
      close_connection(publisher_connection)
    end)

    assert {:ok, _} = AMQP.Queue.declare(publisher_channel, queue, auto_delete: true)
    assert :ok = AMQP.Basic.qos(consumer_one_channel, prefetch_count: 1)
    assert :ok = AMQP.Basic.qos(consumer_two_channel, prefetch_count: 1)

    assert {:ok, "consumer-one"} =
             AMQP.Basic.consume(consumer_one_channel, queue, self(), consumer_tag: "consumer-one")

    assert {:ok, "consumer-two"} =
             AMQP.Basic.consume(consumer_two_channel, queue, self(), consumer_tag: "consumer-two")

    assert :ok = AMQP.Basic.publish(publisher_channel, "", queue, "one")
    assert :ok = AMQP.Basic.publish(publisher_channel, "", queue, "two")

    deliveries = receive_deliveries(%{})

    assert Map.keys(deliveries) |> Enum.sort() == ["consumer-one", "consumer-two"]
    assert :ok = AMQP.Basic.ack(consumer_one_channel, deliveries["consumer-one"].delivery_tag)
    assert :ok = AMQP.Basic.ack(consumer_two_channel, deliveries["consumer-two"].delivery_tag)
  end

  @tag :redelivery
  test "broker redelivers unacknowledged work after consumer connection loss" do
    queue = "network_defense.redelivery.#{System.unique_integer([:positive])}"
    {:ok, publisher_connection} = AMQP.Connection.open(broker_config())
    {:ok, publisher_channel} = AMQP.Channel.open(publisher_connection)
    {:ok, consumer_connection} = AMQP.Connection.open(broker_config())
    {:ok, consumer_channel} = AMQP.Channel.open(consumer_connection)

    on_exit(fn ->
      close_channel(consumer_channel)
      close_connection(consumer_connection)
      delete_queue(publisher_channel, queue)
      close_channel(publisher_channel)
      close_connection(publisher_connection)
    end)

    assert {:ok, _} = AMQP.Queue.declare(publisher_channel, queue)
    assert {:ok, _} = AMQP.Basic.consume(consumer_channel, queue, self(), no_ack: false)
    assert :ok = AMQP.Basic.publish(publisher_channel, "", queue, "redelivery")
    assert_receive {:basic_deliver, "redelivery", _meta}, 5_000

    assert :ok = AMQP.Connection.close(consumer_connection)
    {:ok, replacement_connection} = AMQP.Connection.open(broker_config())
    {:ok, replacement_channel} = AMQP.Channel.open(replacement_connection)

    on_exit(fn ->
      close_channel(replacement_channel)
      close_connection(replacement_connection)
    end)

    assert {:ok, _} = AMQP.Basic.consume(replacement_channel, queue, self(), no_ack: false)

    assert_receive {:basic_deliver, "redelivery",
                    %{delivery_tag: delivery_tag, redelivered: true}},
                   5_000

    assert :ok = AMQP.Basic.ack(replacement_channel, delivery_tag)
  end

  defp receive_deliveries(deliveries) when map_size(deliveries) == 2, do: deliveries

  defp receive_deliveries(deliveries) do
    receive do
      {:basic_deliver, _payload, %{consumer_tag: consumer_tag} = meta}
      when consumer_tag in ["consumer-one", "consumer-two"] ->
        receive_deliveries(Map.put(deliveries, consumer_tag, meta))
    after
      5_000 -> flunk("did not receive work on both consumers")
    end
  end

  defp broker_config do
    password_file = System.fetch_env!("RABBITMQ_INTEGRATION_PASSWORD_FILE")

    [
      host: System.fetch_env!("RABBITMQ_INTEGRATION_HOST"),
      port: integration_port(),
      virtual_host: System.fetch_env!("RABBITMQ_INTEGRATION_VIRTUAL_HOST"),
      username: System.fetch_env!("RABBITMQ_INTEGRATION_USERNAME"),
      password: password_file |> File.read!() |> String.trim()
    ]
  end

  defp integration_port do
    case Integer.parse(System.get_env("RABBITMQ_INTEGRATION_PORT", "5672")) do
      {port, ""} when port > 0 -> port
      _result -> raise "RABBITMQ_INTEGRATION_PORT must be a positive integer"
    end
  end

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

  defp close_connection(connection) do
    AMQP.Connection.close(connection)
  catch
    :exit, _reason -> :ok
  end
end
