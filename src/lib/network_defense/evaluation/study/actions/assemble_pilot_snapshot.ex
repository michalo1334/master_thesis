defmodule NetworkDefense.Evaluation.Study.Actions.AssemblePilotSnapshot do
  @moduledoc false
  @behaviour Gust.Action

  alias NetworkDefense.Evaluation.Study.{
    ActionLoaders,
    Collection,
    CollectionFanIn,
    ExecutionAccess,
    PilotSnapshot,
    Revisions,
    TaskFailure
  }

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  @prepare_task "prepare_pilot_collection"
  @collection_task "collect_pilot_item"
  @replica_position 0

  @impl true
  def execute(_args, %{run_id: run_id}) do
    with {:ok, phase} <- ActionLoaders.pilot_phase_for_run(run_id),
         {:ok, execution} <- ExecutionAccess.fetch_trusted(phase.execution_id),
         {:ok, definition} <- Revisions.load_definition(execution.study_revision_id),
         {:ok, work} <-
           Collection.build_collection_work(execution, phase, definition, @replica_position),
         {:ok, items} <-
           CollectionFanIn.load_items(phase, work, run_id, @prepare_task, @collection_task),
         {:ok, snapshot_id} <-
           PilotSnapshot.assemble_and_store_pilot_snapshot(phase, items, definition) do
      %{"snapshot_id" => snapshot_id}
    else
      :error ->
        TaskFailure.raise_permanent(StudyError.incomplete_pilot_evidence(["collection_items"]))

      {:error, %StudyError{} = error} ->
        TaskFailure.raise_permanent(error)
    end
  end
end
