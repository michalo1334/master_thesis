defmodule NetworkDefense.Compute.RabbitMQ.Envelope do
  @moduledoc false

  @version 1
  @operation_modules %{"simulation" => NetworkDefense.Simulation.SimulationOperation}

  @type work :: %{
          version: 1,
          run_id: binary(),
          partition_id: binary(),
          partition_key: term(),
          work_units: pos_integer(),
          operation: binary(),
          partition: term(),
          trace_headers: %{binary() => binary()}
        }
  @type result :: %{
          version: 1,
          run_id: binary(),
          partition_id: binary(),
          partition_key: term(),
          outcome: {:ok, term()} | {:error, term()}
        }
  @type decoded_work :: map()

  @spec encode_work(work()) :: {:ok, binary()} | {:error, term()}
  def encode_work(work), do: encode(work, &validate_work/1, &Map.delete(&1, :operation_module))

  @spec decode_work(binary()) :: {:ok, decoded_work()} | {:error, term()}
  def decode_work(payload), do: decode(payload, &validate_work/1)

  @spec encode_result(result()) :: {:ok, binary()} | {:error, term()}
  def encode_result(result), do: encode(result, &validate_result/1, & &1)

  @spec decode_result(binary()) :: {:ok, result()} | {:error, term()}
  def decode_result(payload), do: decode(payload, &validate_result/1)

  defp encode(envelope, validator, serializer) do
    with {:ok, envelope} <- validator.(envelope) do
      payload = envelope |> serializer.() |> :erlang.term_to_binary()

      if byte_size(payload) <= max_message_bytes() do
        {:ok, payload}
      else
        {:error, :payload_too_large}
      end
    end
  end

  defp decode(payload, validator) when is_binary(payload) do
    with :ok <- check_size(payload),
         {:ok, envelope} <- safe_binary_to_term(payload) do
      validator.(envelope)
    end
  end

  defp decode(_payload, _validator), do: {:error, :invalid_payload}

  # Sobelow does not recognize the :safe option or the preceding size check.
  # sobelow_skip ["Misc.BinToTerm"]
  defp safe_binary_to_term(payload) do
    # The raw size is checked before safe ETF decoding and the decoded schema is validated.
    {:ok, :erlang.binary_to_term(payload, [:safe])}
  rescue
    ArgumentError -> {:error, :invalid_payload}
  end

  defp validate_work(
         %{
           version: @version,
           run_id: run_id,
           partition_id: partition_id,
           partition_key: partition_key,
           work_units: work_units,
           operation: operation,
           partition: partition,
           trace_headers: trace_headers
         } = envelope
       )
       when map_size(envelope) == 8 do
    with :ok <- validate_identifiers(run_id, partition_id),
         true <- is_integer(work_units) and work_units > 0,
         {:ok, operation_module} <- operation_module(operation),
         true <- valid_trace_headers?(trace_headers) do
      {:ok,
       %{
         version: @version,
         run_id: run_id,
         partition_id: partition_id,
         partition_key: partition_key,
         work_units: work_units,
         operation: operation,
         operation_module: operation_module,
         partition: partition,
         trace_headers: trace_headers
       }}
    else
      false -> {:error, :invalid_work_envelope}
      {:error, _reason} = error -> error
    end
  end

  defp validate_work(%{version: version}) when is_integer(version) and version != @version,
    do: {:error, :unsupported_version}

  defp validate_work(_envelope), do: {:error, :invalid_work_envelope}

  defp validate_result(
         %{
           version: @version,
           run_id: run_id,
           partition_id: partition_id,
           partition_key: partition_key,
           outcome: outcome
         } = envelope
       )
       when map_size(envelope) == 5 do
    with :ok <- validate_identifiers(run_id, partition_id), true <- valid_outcome?(outcome) do
      {:ok,
       %{
         version: @version,
         run_id: run_id,
         partition_id: partition_id,
         partition_key: partition_key,
         outcome: outcome
       }}
    else
      false -> {:error, :invalid_result_envelope}
      {:error, _reason} = error -> error
    end
  end

  defp validate_result(%{version: version}) when is_integer(version) and version != @version,
    do: {:error, :unsupported_version}

  defp validate_result(_envelope), do: {:error, :invalid_result_envelope}

  defp validate_identifiers(run_id, partition_id) do
    if valid_identifier?(run_id) and valid_identifier?(partition_id) do
      :ok
    else
      {:error, :invalid_identifiers}
    end
  end

  defp operation_module(operation) do
    case @operation_modules do
      %{^operation => operation_module} when is_binary(operation) -> {:ok, operation_module}
      _ -> {:error, :unknown_operation}
    end
  end

  defp valid_identifier?(value), do: is_binary(value) and byte_size(value) in 1..255

  defp valid_trace_headers?(headers) when is_map(headers),
    do: Enum.all?(headers, &valid_trace_header?/1)

  defp valid_trace_headers?(_headers), do: false
  defp valid_trace_header?({key, value}), do: is_binary(key) and is_binary(value)
  defp valid_outcome?({status, _value}) when status in [:ok, :error], do: true
  defp valid_outcome?(_outcome), do: false

  defp check_size(payload) do
    if byte_size(payload) <= max_message_bytes(), do: :ok, else: {:error, :payload_too_large}
  end

  defp max_message_bytes do
    :network_defense
    |> Application.fetch_env!(:rabbitmq)
    |> Keyword.fetch!(:max_message_bytes)
  end
end
