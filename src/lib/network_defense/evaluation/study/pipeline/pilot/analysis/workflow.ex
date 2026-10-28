defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.Workflow do
  @moduledoc false

  alias NetworkDefense.Evaluation.EvidenceSnapshots

  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.Contracts.{
    PilotRequest,
    PilotResult
  }

  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.TaskFailure
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Error, as: PilotError

  alias NetworkDefense.Evaluation.Study.Pipeline.GustWaiter
  alias NetworkDefense.Evaluation.WorkflowRun

  alias Gust.DAG.Run.Trigger

  # Separate pilot workflow.
  #
  # The comparison and family workflows must not guess which result shape a
  # run contains, so this module owns pilot submission, waiting, and read-back.

  @dag_name "evaluation_pilot"
  @select_task "select_pilot"

  # The workflow owns the Gust encoding of the typed request. Callers pass the
  # declared contract, so no caller builds run parameters.
  @spec create(PilotRequest.t()) :: {:ok, integer()} | {:error, PilotError.t()}
  def create(%PilotRequest{} = request) do
    with dag when not is_nil(dag) <- Gust.Flows.get_dag_by_name(@dag_name),
         {:ok, run} <-
           Gust.Flows.create_run(%{dag_id: dag.id, params: PilotRequest.to_params(request)}) do
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

  def submit(%PilotRequest{} = request) do
    with {:ok, run_id} <- create(request),
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
    case WorkflowRun.fetch_run(run_id) do
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
    WorkflowRun.failure_or_error(run_id, &decode_task_error/1, &workflow_error/0)
  end

  defp stored_result(run_id) do
    WorkflowRun.stored_result(run_id, @select_task, &invalid_result_error/0)
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
