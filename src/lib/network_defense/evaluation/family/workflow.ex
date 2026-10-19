defmodule NetworkDefense.Evaluation.Family.Workflow do
  @moduledoc false

  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonError
  alias NetworkDefense.Evaluation.Comparison.TaskFailure, as: ComparisonTaskFailure

  alias NetworkDefense.Evaluation.Family.Contracts.{FamilyError, FamilyRequest, FamilyResult}
  alias NetworkDefense.Evaluation.Family.TaskFailure

  alias Gust.DAG.Run.Trigger

  # Separate family workflow.
  #
  # The single-comparison workflow must not guess which result shape a run
  # contains, so this module owns family submission, waiting, and read-back.

  @dag_name "evaluation_family"
  @correct_task "correct_family"
  @poll_interval 100

  def submit(request_map) do
    with dag when not is_nil(dag) <- Gust.Flows.get_dag_by_name(@dag_name),
         {:ok, run} <- Gust.Flows.create_run(%{dag_id: dag.id, params: request_map}) do
      dispatched = Trigger.dispatch_run(run)
      {:ok, dispatched.id}
    else
      _error -> {:error, workflow_error()}
    end
  rescue
    _exception -> {:error, workflow_error()}
  end

  def await(run_id, timeout_ms) when is_integer(timeout_ms) and timeout_ms >= 0 do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    await_loop(run_id, deadline)
  end

  def result(run_id) do
    case fetch_run(run_id) do
      nil ->
        {:error, :not_found}

      %{status: :succeeded, params: params} ->
        with {:ok, request} <- FamilyRequest.parse(params),
             {:ok, stored} <- stored_result(run_id),
             {:ok, result} <- FamilyResult.parse(stored, request) do
          {:ok, result}
        else
          {:error, %FamilyError{} = error} -> {:error, error}
          _invalid -> {:error, invalid_result_error()}
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

  defp await_loop(run_id, deadline) do
    case fetch_run(run_id) do
      nil ->
        {:error, :not_found}

      %{status: :succeeded} ->
        {:ok, :succeeded}

      %{status: :failed} ->
        {:error, failure_for_run(run_id)}

      _run ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :timeout}
        else
          Process.sleep(@poll_interval)
          await_loop(run_id, deadline)
        end
    end
  end

  defp fetch_run(run_id), do: Gust.Repo.get(Gust.Flows.Run, run_id)

  defp stored_result(run_id) do
    case Gust.Flows.get_tasks_by_name(@correct_task, run_id) do
      [%{status: :succeeded, result: result}] when is_map(result) and map_size(result) > 0 ->
        {:ok, result}

      _missing_or_incomplete ->
        {:error, invalid_result_error()}
    end
  end

  # A failed family run can fail in one of two ways. A family task stores a
  # family error. A member task stores the accepted comparison error. Both
  # envelopes are tagged, so the decoder never guesses which shape it has.
  defp decode_task_error(error) do
    case TaskFailure.decode(error) do
      {:ok, family_error} ->
        family_error

      :error ->
        case ComparisonTaskFailure.decode(error) do
          {:ok, %ComparisonError{} = comparison_error} -> as_family_error(comparison_error)
          :error -> workflow_error()
        end
    end
  end

  defp as_family_error(%ComparisonError{} = error) do
    %FamilyError{
      schema_version: error.schema_version,
      code: error.code,
      issues: error.issues,
      schema_errors: error.schema_errors
    }
  end

  defp invalid_result_error,
    do: FamilyError.invalid_result("The stored family result is invalid.")

  defp workflow_error, do: FamilyError.workflow_failed()
end
