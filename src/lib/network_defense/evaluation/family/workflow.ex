defmodule NetworkDefense.Evaluation.Family.Workflow do
  @moduledoc false

  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonError
  alias NetworkDefense.Evaluation.Comparison.TaskFailure, as: ComparisonTaskFailure

  alias NetworkDefense.Evaluation.Family.Contracts.{FamilyError, FamilyRequest, FamilyResult}
  alias NetworkDefense.Evaluation.Family.TaskFailure

  alias NetworkDefense.Evaluation.WorkflowRun

  # Separate family workflow.
  #
  # The single-comparison workflow must not guess which result shape a run
  # contains, so this module owns family submission, waiting, and read-back.

  @dag_name "evaluation_family"
  @correct_task "correct_family"

  def submit(request_map) do
    WorkflowRun.submit(@dag_name, request_map, &FamilyError.workflow_failed/0)
  end

  def await(run_id, timeout_ms) when is_integer(timeout_ms) and timeout_ms >= 0 do
    WorkflowRun.await(run_id, timeout_ms, &failure_for_run/1)
  end

  def result(run_id) do
    case WorkflowRun.fetch_run(run_id) do
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
    WorkflowRun.failure_or_error(run_id, &decode_task_error/1, &workflow_error/0)
  end

  defp stored_result(run_id) do
    WorkflowRun.stored_result(run_id, @correct_task, &invalid_result_error/0)
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
