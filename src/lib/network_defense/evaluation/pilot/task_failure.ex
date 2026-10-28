defmodule NetworkDefense.Evaluation.Pilot.TaskFailure do
  @moduledoc false

  alias NetworkDefense.Evaluation.Pilot.Contracts.PilotError
  alias NetworkDefense.Evaluation.Pilot.TaskFailure.RetryableError
  alias NetworkDefense.Evaluation.Pilot.Wire
  alias NetworkDefense.Evaluation.TaskFailureCodec

  # Bounded persisted task errors for the pilot DAG.
  #
  # The kind tag is pilot-specific, so a persisted pilot failure cannot be
  # decoded as a comparison or family failure.

  @kind "network_defense.evaluation.pilot_error"

  def raise_permanent(error) do
    raise Gust.DAG.NonRecError, message(error)
  end

  def raise_retryable(error) do
    raise RetryableError, message(error)
  end

  def decode(error) do
    TaskFailureCodec.decode(error, @kind, RetryableError, &PilotError.parse_envelope/1)
  end

  defp message(%PilotError{} = error) do
    TaskFailureCodec.encode(error, @kind, &Wire.error/1, &PilotError.workflow_failed/0)
  end
end
