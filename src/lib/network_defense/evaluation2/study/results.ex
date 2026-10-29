defmodule NetworkDefense.Evaluation2.Study.Results do
  @moduledoc false

  # Storage and reads of successful study results.
  #
  # Storage keeps the Final-owned corrected family and the measured timing. The
  # successful execution stays the owner of the revision, the Pilot outcome, and
  # the frozen selection, so the supported result view joins both records.
  #
  # Read-back loads the stored records. It rebuilds no optimization or simulation
  # history.

  alias NetworkDefense.Evaluation2.CorrectedFamily
  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Result
  alias NetworkDefense.Evaluation2.Study.Result.Timing
  alias NetworkDefense.Evaluation2.StudyExecution
  alias NetworkDefense.Evaluation2.StudyResult

  # Storage happens after the Final analysis run succeeded and the lifecycle
  # accepted its output.
  @spec store(StudyExecution.t(), CorrectedFamily.t(), Timing.t()) ::
          {:ok, StudyResult.t()} | {:error, Error.t()}
  def store(_execution, _family, _timing), do: {:error, Placeholder.error(:store)}

  @spec fetch!(Ecto.UUID.t()) :: StudyResult.t()
  def fetch!(_execution_id), do: raise(NotImplementedError, function: :fetch!)

  @spec get(Ecto.UUID.t()) :: {:ok, Result.t()} | {:error, Error.t()}
  def get(_execution_id), do: {:error, Placeholder.error(:get)}
end
