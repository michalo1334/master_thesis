defmodule NetworkDefense.Evaluation2.Study.Executions do
  @moduledoc false

  # Persistence and status reads of study executions.
  #
  # Starting a study writes one execution record in the initial Pilot collection
  # state and begins the study workflow. Pilot analysis acceptance stores the
  # compact outcome on that same record, and resume stores the frozen selection
  # there.
  #
  # The record is the only owner of the compact Pilot outcome and the frozen
  # selection. Accepted phase data stays in phase records.

  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.PilotOutcome
  alias NetworkDefense.Evaluation2.Study.Revision
  alias NetworkDefense.Evaluation2.Study.Selection
  alias NetworkDefense.Evaluation2.Study.Status
  alias NetworkDefense.Evaluation2.StudyExecution

  # Start one execution of a frozen revision and return its status view.
  @spec start(Revision.t()) :: {:ok, Status.t()} | {:error, Error.t()}
  def start(_revision), do: {:error, Placeholder.error(:start)}

  @spec status(Ecto.UUID.t()) :: {:ok, Status.t()} | {:error, Error.t()}
  def status(_execution_id), do: {:error, Placeholder.error(:status)}

  @spec fetch!(Ecto.UUID.t()) :: StudyExecution.t()
  def fetch!(_execution_id), do: raise(NotImplementedError, function: :fetch!)

  @spec put_pilot_outcome(StudyExecution.t(), PilotOutcome.t()) ::
          {:ok, StudyExecution.t()}
  def put_pilot_outcome(_execution, _outcome),
    do: raise(NotImplementedError, function: :put_pilot_outcome)

  @spec put_selection(StudyExecution.t(), Selection.t()) :: {:ok, StudyExecution.t()}
  def put_selection(_execution, _selection),
    do: raise(NotImplementedError, function: :put_selection)
end
