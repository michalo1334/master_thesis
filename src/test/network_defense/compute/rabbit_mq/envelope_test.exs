defmodule NetworkDefense.Compute.RabbitMQ.EnvelopeTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Compute.RabbitMQ.Envelope

  test "round trips work envelopes" do
    assert {:ok, payload} = Envelope.encode_work(work_envelope())

    assert {:ok, decoded} = Envelope.decode_work(payload)
    assert decoded.operation_module == NetworkDefense.Simulation.SimulationOperation
    assert Map.delete(decoded, :operation_module) == work_envelope()
  end

  test "round trips result envelopes" do
    result = %{
      version: 1,
      run_id: "run",
      partition_id: "part",
      partition_key: 7,
      outcome: {:ok, :done}
    }

    assert {:ok, payload} = Envelope.encode_result(result)
    assert {:ok, ^result} = Envelope.decode_result(payload)
  end

  test "rejects malformed envelopes" do
    assert {:error, :invalid_work_envelope} =
             Envelope.decode_work(:erlang.term_to_binary(%{version: 1}))

    assert {:error, :invalid_result_envelope} = Envelope.encode_result(%{version: 1})
  end

  test "rejects unknown versions and operations" do
    assert {:error, :unsupported_version} =
             Envelope.decode_work(:erlang.term_to_binary(%{work_envelope() | version: 2}))

    assert {:error, :unknown_operation} =
             Envelope.decode_work(:erlang.term_to_binary(%{work_envelope() | operation: "other"}))
  end

  test "rejects oversized payloads before decoding" do
    previous = Application.fetch_env!(:network_defense, :rabbitmq)
    Application.put_env(:network_defense, :rabbitmq, Keyword.put(previous, :max_message_bytes, 1))

    on_exit(fn -> Application.put_env(:network_defense, :rabbitmq, previous) end)

    assert {:error, :payload_too_large} =
             Envelope.decode_work(:erlang.term_to_binary(work_envelope()))
  end

  defp work_envelope do
    %{
      version: 1,
      run_id: "run",
      partition_id: "part",
      partition_key: {:batch, 7},
      work_units: 3,
      operation: "simulation",
      partition: %{trial_indexes: 1..3},
      trace_headers: %{"traceparent" => "00-trace"}
    }
  end
end
