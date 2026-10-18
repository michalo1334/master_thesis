defmodule NetworkDefense.Evaluation.Comparison.TaskFailure do
  @moduledoc false

  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonError
  alias NetworkDefense.Evaluation.Comparison.TaskFailure.RetryableError
  alias NetworkDefense.Evaluation.Comparison.Wire

  @kind "network_defense.evaluation.comparison_error"
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
         {:ok, error} <- ComparisonError.parse_envelope(error_map) do
      {:ok, error}
    else
      _other -> :error
    end
  end

  def decode(_error), do: :error

  defp message(%ComparisonError{} = error) do
    envelope = %{"kind" => @kind, "version" => @version, "error" => Wire.error(error)}

    case Jason.encode(envelope) do
      {:ok, encoded} when byte_size(encoded) <= @max_bytes -> encoded
      _other -> fallback_message()
    end
  rescue
    _exception -> fallback_message()
  end

  defp fallback_message do
    error = ComparisonError.workflow_failed()
    Jason.encode!(%{"kind" => @kind, "version" => @version, "error" => Wire.error(error)})
  end
end
