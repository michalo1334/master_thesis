defmodule NetworkDefense.Evaluation.Comparison.Workflow do
  @moduledoc false

  alias NetworkDefense.Evaluation.Comparison.Contracts.{
    ComparisonError,
    ComparisonRequest,
    ComparisonStatistics
  }

  alias Gust.DAG.Run.Trigger
  alias NetworkDefense.Evaluation.Comparison.TaskFailure

  @dag_name "evaluation_comparison"
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

  defp fetch_run(run_id) do
    Gust.Repo.get(Gust.Flows.Run, run_id)
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
