defmodule NetworkDefense.Evaluation2.Study.Views do
  @moduledoc false

  # Construction of the supported study values.
  #
  # Each view joins application-owned records: the revision view from the frozen
  # revision, the status view from the revision and the execution, the Pilot
  # report from the accepted Pilot analysis output, and the result view from the
  # successful execution and its stored result.
  #
  # A view is transient. These functions create no persistence record.
  #
  # The declared graph tier of a comparison is a definition string. The supported
  # comparison identity uses the closed tier order, so a view converts it once.

  alias NetworkDefense.Evaluation2.Contracts.PilotAnalysisContract
  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Study.Comparison
  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Study.PilotResult
  alias NetworkDefense.Evaluation2.Study.Result
  alias NetworkDefense.Evaluation2.Study.Revision
  alias NetworkDefense.Evaluation2.Study.Status
  alias NetworkDefense.Evaluation2.StudyExecution
  alias NetworkDefense.Evaluation2.StudyResult
  alias NetworkDefense.Evaluation2.StudyRevision

  @spec revision(StudyRevision.t()) :: Revision.t()
  def revision(_revision), do: raise(NotImplementedError, function: :revision)

  @spec status(StudyRevision.t(), StudyExecution.t()) :: Status.t()
  def status(_revision, _execution), do: raise(NotImplementedError, function: :status)

  @spec pilot_result(StudyRevision.t(), PilotAnalysisContract.Output.t()) :: PilotResult.t()
  def pilot_result(_revision, _output),
    do: raise(NotImplementedError, function: :pilot_result)

  @spec result(StudyRevision.t(), StudyExecution.t(), StudyResult.t()) :: Result.t()
  def result(_revision, _execution, _stored_result),
    do: raise(NotImplementedError, function: :result)

  @spec comparison(Definition.comparison()) :: Comparison.t()
  def comparison(_declared_comparison),
    do: raise(NotImplementedError, function: :comparison)
end
