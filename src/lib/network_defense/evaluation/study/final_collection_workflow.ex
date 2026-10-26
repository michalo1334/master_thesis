defmodule NetworkDefense.Evaluation.Study.FinalCollectionWorkflow do
  @moduledoc false

  alias Gust.DAG.Run.Trigger
  alias NetworkDefense.Evaluation.Study.{Collection, GustWaiter, Revisions}
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase}
  alias NetworkDefense.Repo

  @dag_name "evaluation_study_final_collection"
  @result_task "assemble_final_snapshot"

  @spec create(StudyPhase.t()) :: {:ok, integer()} | {:error, StudyError.t()}
  def create(%StudyPhase{} = phase) do
    with {:ok, execution} <- load_execution(phase.execution_id),
         {:ok, definition} <- Revisions.load_definition(execution.study_revision_id),
         {:ok, _work} <- Collection.build_collection_work(execution, phase, definition, 0),
         %{id: dag_id} <- Gust.Flows.get_dag_by_name(@dag_name),
         {:ok, run} <-
           Gust.Flows.create_run(%{dag_id: dag_id, params: %{"study_phase_id" => phase.id}}) do
      {:ok, run.id}
    else
      {:error, %StudyError{} = error} -> {:error, error}
      _error -> {:error, StudyError.final_collection_workflow_failed()}
    end
  rescue
    _exception in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:error, StudyError.final_collection_workflow_failed()}
  end

  @spec dispatch(integer()) :: :ok | {:error, StudyError.t()}
  def dispatch(run_id) do
    run = Gust.Flows.get_run!(run_id)
    _dispatched = Trigger.dispatch_run(run)
    :ok
  rescue
    _exception in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:error, StudyError.final_collection_workflow_failed()}
  end

  @spec await(integer(), timeout()) :: {:ok, Ecto.UUID.t()} | {:error, StudyError.t()}
  def await(run_id, timeout \\ :infinity) do
    case GustWaiter.await(run_id, timeout) do
      {:ok, :succeeded} -> result(run_id)
      {:error, _reason} -> {:error, StudyError.final_collection_workflow_failed()}
    end
  end

  @spec result(integer()) :: {:ok, Ecto.UUID.t()} | {:error, StudyError.t()}
  def result(run_id) do
    case Gust.Flows.get_tasks_by_name(@result_task, run_id) do
      [%{status: :succeeded, result: %{"snapshot_id" => snapshot_id}}] ->
        case Ecto.UUID.cast(snapshot_id) do
          {:ok, id} -> {:ok, id}
          :error -> {:error, StudyError.final_collection_workflow_failed()}
        end

      _missing_or_invalid ->
        {:error, StudyError.final_collection_workflow_failed()}
    end
  rescue
    _exception in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:error, StudyError.final_collection_workflow_failed()}
  end

  defp load_execution(execution_id) do
    case Repo.get(StudyExecution, execution_id) do
      %StudyExecution{} = execution -> {:ok, execution}
      nil -> {:error, StudyError.study_execution_not_found()}
    end
  end
end
