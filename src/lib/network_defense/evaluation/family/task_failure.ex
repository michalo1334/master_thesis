defmodule NetworkDefense.Evaluation.Family.TaskFailure do
  @moduledoc false

  alias NetworkDefense.Evaluation.Family.Contracts.FamilyError
  alias NetworkDefense.Evaluation.Family.TaskFailure.RetryableError
  alias NetworkDefense.Evaluation.Family.Wire
  alias NetworkDefense.Evaluation.TaskFailureCodec

  # Bounded persisted task errors for the family DAG.
  #
  # The kind tag is family-specific, so a persisted family failure cannot be
  # decoded as a comparison failure.

  @kind "network_defense.evaluation.family_error"

  def raise_permanent(error) do
    raise Gust.DAG.NonRecError, message(error)
  end

  def raise_retryable(error) do
    raise RetryableError, message(error)
  end

  def decode(error) do
    TaskFailureCodec.decode(error, @kind, RetryableError, &FamilyError.parse_envelope/1)
  end

  defp message(%FamilyError{} = error) do
    TaskFailureCodec.encode(error, @kind, &Wire.error/1, &FamilyError.workflow_failed/0)
  end
end
