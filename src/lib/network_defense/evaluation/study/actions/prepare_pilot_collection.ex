defmodule NetworkDefense.Evaluation.Study.Actions.PreparePilotCollection do
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

  @replica_position 0

  @impl true
  def execute(_args, %{run_id: run_id}) do
    with {:ok, phase} <- ActionLoaders.pilot_phase_for_run(run_id),
         {:ok, execution} <- ExecutionAccess.fetch_trusted(phase.execution_id),
         {:ok, definition} <- Revisions.load_definition(execution.study_revision_id),
         {:ok, work} <-
           Collection.build_collection_work(execution, phase, definition, @replica_position),
         {:ok, items} <- prepare_items(phase, work) do
      %{
        "gust_task_items" => Enum.map(items, fn item -> %{"collection_item_id" => item.id} end)
      }
    else
      {:error, %StudyError{} = error} -> TaskFailure.raise_permanent(error)
    end
  end

  defp prepare_items(phase, work) do
    work
    |> Enum.reduce_while({:ok, []}, fn work_item, {:ok, items} ->
      case CollectionItems.get_or_create(
             phase.id,
             @replica_position,
             work_item.item_position
           ) do
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
