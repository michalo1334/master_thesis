defmodule NetworkDefense.Evaluation.Family.TaskFailure do
  @moduledoc false

  alias NetworkDefense.Evaluation.Family.Contracts.FamilyError
  alias NetworkDefense.Evaluation.Family.TaskFailure.RetryableError
  alias NetworkDefense.Evaluation.Family.Wire

  # Bounded persisted task errors for the family DAG.
  #
  # The kind tag is family-specific, so a persisted family failure cannot be
  # decoded as a comparison failure.

  @kind "network_defense.evaluation.family_error"
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
         {:ok, error} <- FamilyError.parse_envelope(error_map) do
      {:ok, error}
    else
      _other -> :error
    end
  end

  def decode(_error), do: :error

  defp message(%FamilyError{} = error) do
    envelope = %{"kind" => @kind, "version" => @version, "error" => Wire.error(error)}

    case Jason.encode(envelope) do
      {:ok, encoded} when byte_size(encoded) <= @max_bytes -> encoded
      _other -> fallback_message()
    end
  rescue
    _exception -> fallback_message()
  end

  defp fallback_message do
    error = FamilyError.workflow_failed()
    Jason.encode!(%{"kind" => @kind, "version" => @version, "error" => Wire.error(error)})
  end
end
