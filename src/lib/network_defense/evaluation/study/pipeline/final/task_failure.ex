defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.TaskFailure do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Wire
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Error, as: FinalError
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.TaskFailure.RetryableError
  alias NetworkDefense.Evaluation.TaskFailureCodec

  # Bounded persisted task errors for the Final DAG.
  #
  # The kind tag is Final-specific, so a persisted Final failure cannot be
  # decoded as a comparison, family, or pilot failure.

  @kind "network_defense.evaluation.final_error"

  def raise_permanent(error) do
    raise Gust.DAG.NonRecError, message(error)
  end

  def raise_retryable(error) do
    raise RetryableError, message(error)
  end

  def decode(error) do
    TaskFailureCodec.decode(error, @kind, RetryableError, &FinalError.parse_envelope/1)
  end

  defp message(%FinalError{} = error) do
    TaskFailureCodec.encode(error, @kind, &Wire.error/1, &FinalError.workflow_failed/0)
  end
end
