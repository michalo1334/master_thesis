defmodule NetworkDefense.Evaluation.Study.Actions.PrepareFinalReplica do
  @moduledoc false
  @behaviour Gust.Action

  alias NetworkDefense.Evaluation.Study.{
    ActionLoaders,
    Collection,
    CollectionItems,
    ExecutionAccess,
    Revisions,
    TaskFailure
  }

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.StudyPhaseRun
  alias NetworkDefense.Repo

  @impl true
  def execute(args, _context) do
    with {:ok, phase_run_id} <- fetch_id(args, :study_phase_run_id),
         {:ok, replica_position} <- fetch_position(args),
         {:ok, phase_run} <- load_phase_run(phase_run_id),
         {:ok, phase} <- ActionLoaders.final_phase(phase_run.study_phase_id),
         {:ok, execution} <- ExecutionAccess.fetch_trusted(phase.execution_id),
         {:ok, definition} <- Revisions.load_definition(execution.study_revision_id),
         {:ok, work} <-
           Collection.build_collection_work(execution, phase, definition, replica_position),
         {:ok, tier_work} <- Collection.filter_tier(work, definition, phase_run.tier),
         {:ok, items} <- prepare_items(phase, replica_position, tier_work) do
      %{"gust_task_items" => Enum.map(items, &%{"collection_item_id" => &1.id})}
    else
      {:error, %StudyError{} = error} ->
        TaskFailure.raise_permanent(error)
    end
  end

  defp fetch_id(args, key) do
    case Keyword.fetch(args, key) do
      {:ok, value} ->
        case Ecto.UUID.cast(value) do
          {:ok, id} -> {:ok, id}
          :error -> {:error, StudyError.invalid_study_phase()}
        end

      :error ->
        {:error, StudyError.invalid_study_phase()}
    end
  end

  defp fetch_position(args) do
    case Keyword.fetch(args, :replica_position) do
      {:ok, position} when is_integer(position) and position in -1..4 -> {:ok, position}
      _ -> {:error, StudyError.invalid_collection_position(:replica_position)}
    end
  end

  defp load_phase_run(id) do
    case Repo.get(StudyPhaseRun, id) do
      %StudyPhaseRun{} = phase_run -> {:ok, phase_run}
      nil -> {:error, StudyError.phase_run_storage_failed()}
    end
  end

  defp prepare_items(phase, replica_position, work) do
    Enum.reduce_while(work, {:ok, []}, fn work_item, {:ok, items} ->
      case CollectionItems.get_or_create(phase.id, replica_position, work_item.item_position) do
        {:ok, item} -> {:cont, {:ok, [item | items]}}
        {:error, %StudyError{} = error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end
end
