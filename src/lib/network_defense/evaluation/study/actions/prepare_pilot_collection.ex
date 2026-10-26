defmodule NetworkDefense.Evaluation.Study.Actions.PreparePilotCollection do
  @moduledoc false
  @behaviour Gust.Action

  alias NetworkDefense.Evaluation.Study.{Collection, CollectionItems, Revisions, TaskFailure}
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase}
  alias NetworkDefense.Repo

  @replica_position 0

  @impl true
  def execute(_args, %{run_id: run_id}) do
    with {:ok, phase} <- load_phase(run_id),
         {:ok, execution} <- load_execution(phase.execution_id),
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
