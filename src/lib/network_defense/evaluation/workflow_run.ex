defmodule NetworkDefense.Evaluation.WorkflowRun do
  @moduledoc false

  alias Gust.DAG.Run.Trigger

  @poll_interval 100

  def submit(dag_name, request_map, workflow_error) do
    with dag when not is_nil(dag) <- Gust.Flows.get_dag_by_name(dag_name),
         {:ok, run} <- Gust.Flows.create_run(%{dag_id: dag.id, params: request_map}) do
      dispatched = Trigger.dispatch_run(run)
      {:ok, dispatched.id}
    else
      _error -> {:error, workflow_error.()}
    end
  rescue
    _exception -> {:error, workflow_error.()}
  end

  def fetch_run(run_id), do: Gust.Repo.get(Gust.Flows.Run, run_id)

  # Comparison, Family, and Pilot bound all exceptions at this boundary.
  # Final calls failure_for_run/3 and keeps its database-only rescue.
  def failure_or_error(run_id, decode_error, workflow_error) do
    failure_for_run(run_id, decode_error, workflow_error)
  rescue
    _exception -> workflow_error.()
  end

  def failure_for_run(run_id, decode_error, workflow_error) do
    run_id
    |> Gust.Flows.get_run_with_tasks!()
    |> Map.fetch!(:tasks)
    |> Enum.find(&(&1.status == :failed))
    |> case do
      nil -> workflow_error.()
      task -> decode_error.(task.error)
    end
  end

  def stored_result(run_id, task_name, invalid_result) do
    case Gust.Flows.get_tasks_by_name(task_name, run_id) do
      [%{status: :succeeded, result: result}] when is_map(result) and map_size(result) > 0 ->
        {:ok, result}

      _missing_or_incomplete ->
        {:error, invalid_result.()}
    end
  end

  def await(run_id, timeout_ms, failure_for_run) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    await_loop(run_id, deadline, failure_for_run)
  end

  defp await_loop(run_id, deadline, failure_for_run) do
    case fetch_run(run_id) do
      nil ->
        {:error, :not_found}

      %{status: :succeeded} ->
        {:ok, :succeeded}

      %{status: :failed} ->
        {:error, failure_for_run.(run_id)}

      _run ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :timeout}
        else
          Process.sleep(@poll_interval)
          await_loop(run_id, deadline, failure_for_run)
        end
    end
  end
end
