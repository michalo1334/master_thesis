defmodule NetworkDefense.Evaluation2.Study.Result do
  @moduledoc """
  Stored result of a successful study.

  Result storage keeps the compact Pilot outcome, the frozen selection, the
  corrected Final family, and the measured timing. Read-back returns the stored
  record; it rebuilds no optimization or simulation history.
  """

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation2.CorrectedFamily
  alias NetworkDefense.Evaluation2.{NotImplementedError, StudyExecution, StudyResult}
  alias NetworkDefense.Evaluation2.Timing.TimingSummary

  @doc """
  Store the result of one successful execution.

  Storage happens after the Final analysis run succeeded and the lifecycle
  accepted its output.
  """
  @spec store(StudyExecution.t(), CorrectedFamily.t(), TimingSummary.t()) ::
          {:ok, StudyResult.t()} | {:error, StudyError.t()}
  def store(_execution, _family, _timing), do: raise(NotImplementedError, function: :store)

  @doc """
  Read the stored result of one execution.

  Scaffold: returns `{:error, :not_implemented}`.
  """
  @spec get(Ecto.UUID.t()) ::
          {:ok, StudyResult.t()} | {:error, StudyError.t() | :not_implemented}
  def get(_execution_id), do: {:error, :not_implemented}
end
