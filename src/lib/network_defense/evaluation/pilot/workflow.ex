defmodule NetworkDefense.Evaluation.Pilot.Workflow do
  @moduledoc false

  alias NetworkDefense.Evaluation.EvidenceSnapshots

  alias NetworkDefense.Evaluation.Pilot.Contracts.{
    PilotError,
    PilotRequest,
    PilotResult
  }

  alias NetworkDefense.Evaluation.Pilot.TaskFailure
  alias NetworkDefense.Evaluation.Study.GustWaiter

  alias Gust.DAG.Run.Trigger

  # Separate pilot workflow.
  #
  # The comparison and family workflows must not guess which result shape a
  # run contains, so this module owns pilot submission, waiting, and read-back.

  @dag_name "evaluation_pilot"
  @select_task "select_pilot"
  def create(request_map) do
    with dag when not is_nil(dag) <- Gust.Flows.get_dag_by_name(@dag_name),
         {:ok, run} <- Gust.Flows.create_run(%{dag_id: dag.id, params: request_map}) do
      {:ok, run.id}
    else
      _error -> {:error, workflow_error()}
    end
  rescue
    _exception -> {:error, workflow_error()}
  end

  def dispatch(run_id) do
    run = Gust.Flows.get_run!(run_id)
    _dispatched = Trigger.dispatch_run(run)
    :ok
  rescue
    _exception -> {:error, workflow_error()}
  end

  def submit(request_map) do
    with {:ok, run_id} <- create(request_map),
         :ok <- dispatch(run_id) do
      {:ok, run_id}
    end
  end

  def await(run_id), do: await(run_id, :infinity)

  def await(run_id, timeout)
      when timeout == :infinity or (is_integer(timeout) and timeout >= 0) do
    case GustWaiter.await(run_id, timeout) do
      {:ok, :succeeded} -> {:ok, :succeeded}
      {:error, :failed} -> {:error, failure_for_run(run_id)}
      {:error, :unavailable} -> {:error, workflow_error()}
      {:error, reason} -> {:error, reason}
    end
  end

  def result(run_id) do
    case fetch_run(run_id) do
      nil ->
        {:error, :not_found}

      %{status: :succeeded, params: params} ->
        with {:ok, request} <- PilotRequest.parse(params),
             {:ok, snapshot, payload} <- EvidenceSnapshots.load(request.snapshot_id),
             :ok <- PilotRequest.matches_snapshot(request, snapshot, payload),
             {:ok, stored} <- stored_result(run_id),
             {:ok, result} <- PilotResult.parse(stored, request, payload) do
          {:ok, result}
        else
          {:error, %PilotError{} = error} -> {:error, error}
        end

      %{status: :failed} ->
        {:error, failure_for_run(run_id)}

      _active_run ->
        {:error, :not_ready}
    end
  rescue
    _exception -> {:error, workflow_error()}
  end

  def failure_for_run(run_id) do
    run_id
    |> Gust.Flows.get_run_with_tasks!()
    |> Map.fetch!(:tasks)
    |> Enum.find(&(&1.status == :failed))
    |> case do
      nil -> workflow_error()
      task -> decode_task_error(task.error)
    end
  rescue
    _exception -> workflow_error()
  end

  defp fetch_run(run_id), do: Gust.Repo.get(Gust.Flows.Run, run_id)

  defp stored_result(run_id) do
    case Gust.Flows.get_tasks_by_name(@select_task, run_id) do
      [%{status: :succeeded, result: result}] when is_map(result) and map_size(result) > 0 ->
        {:ok, result}

      _missing_or_incomplete ->
        {:error, invalid_result_error()}
    end
  end

  defp decode_task_error(error) do
    case TaskFailure.decode(error) do
      {:ok, pilot_error} -> pilot_error
      :error -> workflow_error()
    end
  end

  defp invalid_result_error,
    do: PilotError.invalid_result("The stored pilot result is invalid.")

  defp workflow_error, do: PilotError.workflow_failed()
end
