defmodule NetworkDefense.Evaluation.Study.Actions.AssemblePilotSnapshot do
  @moduledoc false
  @behaviour Gust.Action

  import Ecto.Query

  alias NetworkDefense.Evaluation.Study.{Collection, PilotSnapshot, Revisions, TaskFailure}
  alias NetworkDefense.Evaluation.Study.Contracts.{CollectionResult, StudyError}
  alias NetworkDefense.Evaluation.{StudyCollectionItem, StudyExecution, StudyPhase}
  alias NetworkDefense.Repo

  @prepare_task "prepare_pilot_collection"
  @collection_task "collect_pilot_item"
  @replica_position 0

  @impl true
  def execute(_args, %{run_id: run_id}) do
    with {:ok, phase} <- load_phase(run_id),
         {:ok, execution} <- load_execution(phase.execution_id),
         {:ok, definition} <- Revisions.load_definition(execution.study_revision_id),
         {:ok, work} <-
           Collection.build_collection_work(execution, phase, definition, @replica_position),
         {:ok, items, payloads} <- authoritative_items(phase, work),
         :ok <- validate_preparation(run_id, payloads),
         :ok <- validate_mapped_tasks(run_id, payloads, items),
         {:ok, snapshot_id} <-
           PilotSnapshot.assemble_and_store_pilot_snapshot(phase, items, definition) do
      %{"snapshot_id" => snapshot_id}
    else
      {:error, %StudyError{} = error} -> TaskFailure.raise_permanent(error)
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

  defp authoritative_items(%StudyPhase{id: phase_id}, work) do
    items =
      Repo.all(
        from item in StudyCollectionItem,
          where:
            item.study_phase_id == ^phase_id and
              item.replica_position == @replica_position,
          order_by: item.item_position
      )

    expected_positions = Enum.map(work, & &1.item_position)

    if Enum.map(items, & &1.item_position) == expected_positions do
      payloads = Enum.map(items, &%{"collection_item_id" => &1.id})
      {:ok, items, payloads}
    else
      incomplete()
    end
  end

  defp validate_preparation(run_id, payloads) do
    case Gust.Flows.get_tasks_by_name(@prepare_task, run_id) do
      [%{status: :succeeded, result: %{"gust_task_items" => ^payloads}}] -> :ok
      _missing_or_changed -> incomplete()
    end
  end

  defp validate_mapped_tasks(run_id, payloads, items) do
    tasks = Gust.Flows.get_tasks_by_name(@collection_task, run_id)

    expected_indices =
      case length(payloads) do
        0 -> []
        count -> Enum.to_list(0..(count - 1))
      end

    if length(tasks) == length(payloads) and Enum.map(tasks, & &1.map_index) == expected_indices do
      tasks
      |> Enum.zip(payloads)
      |> Enum.zip(items)
      |> Enum.reduce_while(:ok, &validate_mapped_task/2)
    else
      incomplete()
    end
  end

  defp validate_mapped_task({{task, payload}, item}, :ok) do
    case validate_task(task, payload, item) do
      :ok -> {:cont, :ok}
      {:error, %StudyError{} = error} -> {:halt, {:error, error}}
    end
  end

  defp validate_task(
         %{status: :succeeded, params: payload, result: result},
         payload,
         %StudyCollectionItem{} = item
       )
       when is_map(result) do
    case CollectionResult.new(result) do
      {:ok, receipt}
      when receipt.collection_item_id == item.id and
             receipt.replica_position == item.replica_position and
             receipt.item_position == item.item_position ->
        :ok

      _invalid ->
        incomplete()
    end
  end

  defp validate_task(_task, _payload, _item), do: incomplete()

  defp incomplete, do: {:error, StudyError.incomplete_pilot_evidence(["collection_items"])}
end
