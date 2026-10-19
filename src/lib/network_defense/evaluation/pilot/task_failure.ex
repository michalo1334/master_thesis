defmodule NetworkDefense.Evaluation.Pilot.TaskFailure do
  @moduledoc false

  alias NetworkDefense.Evaluation.Pilot.Contracts.PilotError
  alias NetworkDefense.Evaluation.Pilot.TaskFailure.RetryableError
  alias NetworkDefense.Evaluation.Pilot.Wire

  # Bounded persisted task errors for the pilot DAG.
  #
  # The kind tag is pilot-specific, so a persisted pilot failure cannot be
  # decoded as a comparison or family failure.

  @kind "network_defense.evaluation.pilot_error"
  @version 1
  @max_bytes 65_536
  @retryable_type inspect(RetryableError)

  def raise_permanent(error) do
    raise Gust.DAG.NonRecError, message(error)
  end

  def raise_retryable(error) do
    raise RetryableError, message(error)
  end

  def decode(%{"type" => type, "message" => message})
      when type in ["Gust.DAG.NonRecError", @retryable_type] and is_binary(message) and
             byte_size(message) <= @max_bytes do
    with {:ok, envelope} <- Jason.decode(message),
         %{"kind" => @kind, "version" => @version, "error" => error_map} <- envelope,
         {:ok, error} <- PilotError.parse_envelope(error_map) do
      {:ok, error}
    else
      _other -> :error
    end
  end

  def decode(_error), do: :error

  defp message(%PilotError{} = error) do
    envelope = %{"kind" => @kind, "version" => @version, "error" => Wire.error(error)}

    case Jason.encode(envelope) do
      {:ok, encoded} when byte_size(encoded) <= @max_bytes -> encoded
      _other -> fallback_message()
    end
  rescue
    _exception -> fallback_message()
  end

  defp fallback_message do
    error = PilotError.workflow_failed()
    Jason.encode!(%{"kind" => @kind, "version" => @version, "error" => Wire.error(error)})
  end
end
