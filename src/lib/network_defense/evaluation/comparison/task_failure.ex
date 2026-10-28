defmodule NetworkDefense.Evaluation.Comparison.TaskFailure do
  @moduledoc false

  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonError
  alias NetworkDefense.Evaluation.Comparison.TaskFailure.RetryableError
  alias NetworkDefense.Evaluation.Comparison.Wire
  alias NetworkDefense.Evaluation.TaskFailureCodec

  @kind "network_defense.evaluation.comparison_error"

  def raise_permanent(error) do
    raise Gust.DAG.NonRecError, message(error)
  end

  def raise_retryable(error) do
    raise RetryableError, message(error)
  end

  def decode(error) do
    TaskFailureCodec.decode(error, @kind, RetryableError, &ComparisonError.parse_envelope/1)
  end

  defp message(%ComparisonError{} = error) do
    TaskFailureCodec.encode(error, @kind, &Wire.error/1, &ComparisonError.workflow_failed/0)
  end
end
