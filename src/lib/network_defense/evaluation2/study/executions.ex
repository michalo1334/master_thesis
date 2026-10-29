defmodule NetworkDefense.Evaluation2.Study.Executions do
  @moduledoc """
  Persistence and status reads of study executions.

  Starting a study writes one execution record in the initial Pilot collection
  state and begins the study workflow. Pilot analysis acceptance stores the
  compact outcome on that same record.
  """

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.{PilotOutcome, StudyExecution}

  @doc """
  Start one execution of a frozen revision.

  The new record holds the revision reference, the initial lifecycle state, and
  no Pilot outcome. Final selection fields stay empty until approval. Scaffold:
  returns `{:error, :not_implemented}`.
  """
  @spec start(Ecto.UUID.t()) ::
          {:ok, StudyExecution.t()} | {:error, StudyError.t() | :not_implemented}
  def start(_revision_id), do: {:error, :not_implemented}

  @doc """
  Read the current record of one execution.

  Scaffold: returns `{:error, :not_implemented}`.
  """
  @spec status(Ecto.UUID.t()) ::
          {:ok, StudyExecution.t()} | {:error, StudyError.t() | :not_implemented}
  def status(_execution_id), do: {:error, :not_implemented}

  @doc """
  Store the compact Pilot outcome on one execution.

  Complete candidate summaries stay in the terminal Pilot analysis result.
  """
  @spec put_pilot_outcome(StudyExecution.t(), PilotOutcome.t()) ::
          {:ok, StudyExecution.t()}
  def put_pilot_outcome(_execution, _outcome),
    do: raise(NotImplementedError, function: :put_pilot_outcome)
end
