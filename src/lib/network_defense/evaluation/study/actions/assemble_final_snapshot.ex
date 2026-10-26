defmodule NetworkDefense.Evaluation.Study.Actions.AssembleFinalSnapshot do
  @moduledoc false
  @behaviour Gust.Action

  alias NetworkDefense.Evaluation.Study.{
    Collection,
    CollectionFanIn,
    FinalSnapshot,
    Revisions,
    TaskFailure
  }

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase}
  alias NetworkDefense.Repo

  @prepare_task "prepare_final_collection"
  @collection_task "collect_final_item"
  @replica_position 0

  @impl true
  def execute(_args, %{run_id: run_id}) do
    with {:ok, phase} <- load_phase(run_id),
         {:ok, execution} <- load_execution(phase.execution_id),
         {:ok, definition} <- Revisions.load_definition(execution.study_revision_id),
         {:ok, work} <-
           Collection.build_collection_work(execution, phase, definition, @replica_position),
         {:ok, items} <-
           CollectionFanIn.load_items(phase, work, run_id, @prepare_task, @collection_task),
         {:ok, snapshot_id} <- FinalSnapshot.assemble_and_store(phase, items, definition) do
      %{"snapshot_id" => snapshot_id}
    else
      :error ->
        TaskFailure.raise_permanent(StudyError.incomplete_final_evidence(["collection_items"]))

      {:error, %StudyError{} = error} ->
        TaskFailure.raise_permanent(error)
    end
  end

  defp load_phase(run_id) do
    with %{params: %{"study_phase_id" => phase_id}} <- Gust.Flows.get_run!(run_id),
         {:ok, id} <- Ecto.UUID.cast(phase_id),
         %StudyPhase{} = phase <- Repo.get(StudyPhase, id) do
      {:ok, phase}
    else
      _invalid -> {:error, StudyError.invalid_study_phase()}
    end
  end

  defp load_execution(execution_id) do
    case Repo.get(StudyExecution, execution_id) do
      %StudyExecution{} = execution -> {:ok, execution}
      nil -> {:error, StudyError.study_execution_not_found()}
    end
  end
end
