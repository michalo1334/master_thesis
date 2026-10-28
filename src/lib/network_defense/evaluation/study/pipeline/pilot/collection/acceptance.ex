defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.Acceptance do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.IO, as: AnalysisIO
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.IO
  alias NetworkDefense.Evaluation.Study.Pipeline.State
  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase}
  alias NetworkDefense.Repo

  # Pilot collection owns its successful transition: accept the snapshot under
  # the execution lock, then hand Pilot analysis its stage input.
  @phase :pilot_collection
  @analysis_phase :pilot_analysis
  @active_state :collecting_pilot

  @spec accept_snapshot(IO.t(), Ecto.UUID.t()) ::
          {:ok, AnalysisIO.t()} | {:error, StudyError.t()} | {:stop, atom()}
  def accept_snapshot(%IO{} = io, snapshot_id) when is_binary(snapshot_id) do
    case State.transaction(io.execution.id, &lock_and_accept(&1, snapshot_id)) do
      {:ok, %StudyPhase{} = analysis_phase} ->
        {:ok, AnalysisIO.from_collection(%{io | snapshot_id: snapshot_id}, analysis_phase)}

      other ->
        other
    end
  end

  def accept_snapshot(%IO{}, _snapshot_id), do: {:error, StudyError.collection_workflow_failed()}

  defp lock_and_accept(%StudyExecution{state: @active_state} = execution, snapshot_id) do
    phase = State.lock_named_phase(execution.id, @phase)

    if is_nil(phase.snapshot_id) or phase.snapshot_id == snapshot_id do
      State.update_phase!(phase, %{snapshot_id: snapshot_id})
      _transitioned = State.transition!(execution, :pilot_collected)
      {:ok, analysis_phase!(execution.id)}
    else
      Repo.rollback({:error, StudyError.collection_workflow_failed()})
    end
  end

  defp lock_and_accept(%StudyExecution{state: state}, _snapshot_id), do: State.stop(state)

  # One analysis phase per execution. A repeated acceptance reuses the stored
  # row, and the unique index rejects a concurrent duplicate insert.
  defp analysis_phase!(execution_id) do
    case Repo.get_by(StudyPhase, execution_id: execution_id, phase: @analysis_phase) do
      %StudyPhase{} = phase ->
        phase

      nil ->
        %StudyPhase{}
        |> StudyPhase.changeset(%{execution_id: execution_id, phase: @analysis_phase})
        |> Repo.insert()
        |> case do
          {:ok, %StudyPhase{} = phase} -> phase
          {:error, _changeset} -> Repo.rollback({:error, StudyError.pilot_analysis_failed()})
        end
    end
  end
end
