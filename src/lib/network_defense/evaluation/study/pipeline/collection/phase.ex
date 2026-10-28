defmodule NetworkDefense.Evaluation.Study.Pipeline.Collection.Phase do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase}
  alias NetworkDefense.Repo

  # The collection phase invariant.
  #
  # A collection phase is one of the two declared phases, and it belongs to the
  # execution that requested the work. Planning and running both enforce it.

  @supported [:pilot_collection, :final_collection]

  @spec ensure_supported(StudyPhase.t()) :: :ok | {:error, StudyError.t()}
  def ensure_supported(%StudyPhase{phase: phase}) do
    if phase in @supported,
      do: :ok,
      else: {:error, StudyError.unsupported_collection_phase(phase)}
  end

  @spec ensure_belongs_to(StudyExecution.t(), StudyPhase.t()) ::
          :ok | {:error, StudyError.t()}
  def ensure_belongs_to(%StudyExecution{id: execution_id}, %StudyPhase{} = phase) do
    if phase.execution_id == execution_id,
      do: :ok,
      else: {:error, StudyError.collection_phase_mismatch()}
  end

  @terminal [:awaiting_final, :succeeded, :failed, :cancelled]

  # Both collection stages read their own stored phase through one lookup.
  @spec fetch(StudyExecution.t(), atom()) :: {:ok, StudyPhase.t()} | {:error, StudyError.t()}
  def fetch(%StudyExecution{id: execution_id}, phase) when phase in @supported do
    case Repo.get_by(StudyPhase, execution_id: execution_id, phase: phase) do
      %StudyPhase{} = stored -> {:ok, stored}
      nil -> {:error, StudyError.invalid_study_phase()}
    end
  end

  # The stored state is authoritative. A finished, cancelled or paused study
  # stops the stage; any other mismatch has no phase for this stage.
  @spec ensure_active(StudyExecution.t(), atom()) ::
          :ok | {:stop, atom()} | {:error, StudyError.t()}
  def ensure_active(%StudyExecution{state: state}, state), do: :ok

  def ensure_active(%StudyExecution{state: state}, _expected) when state in @terminal,
    do: {:stop, state}

  def ensure_active(%StudyExecution{}, _expected),
    do: {:error, StudyError.study_execution_not_found()}
end
