defmodule NetworkDefense.Evaluation.Comparison.Workflow do
  @moduledoc false

  alias NetworkDefense.Evaluation.Comparison.Contracts.{
    ComparisonError,
    ComparisonRequest,
    ComparisonStatistics
  }

  alias NetworkDefense.Evaluation.Comparison.TaskFailure
  alias NetworkDefense.Evaluation.WorkflowRun

  @dag_name "evaluation_comparison"

  def submit(request_map) do
    WorkflowRun.submit(@dag_name, request_map, &ComparisonError.workflow_failed/0)
  end

  def await(run_id, timeout_ms) when is_integer(timeout_ms) and timeout_ms >= 0 do
    WorkflowRun.await(run_id, timeout_ms, &failure_for_run/1)
  end

  def result(run_id) do
    case WorkflowRun.fetch_run(run_id) do
      nil ->
        {:error, :not_found}

      %{status: :succeeded, params: params} ->
        with result <- Gust.Flows.get_task_result_by_name_run!("compare", run_id),
             {:ok, request} <- ComparisonRequest.parse(params),
             {:ok, statistics} <- ComparisonStatistics.parse(result, request) do
          {:ok, statistics}
        else
          _error -> {:error, invalid_result_error()}
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

  defp decode_task_error(error) do
    case TaskFailure.decode(error) do
      {:ok, comparison_error} -> comparison_error
      :error -> workflow_error()
    end
  end

  defp invalid_result_error,
    do: ComparisonError.invalid_response_contract("The stored comparison result is invalid.")

  defp workflow_error, do: ComparisonError.workflow_failed()
end
