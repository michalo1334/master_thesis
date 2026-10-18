defmodule NetworkDefense.Evaluation.Comparison.Actions.PrototypeCompare do
  @moduledoc false
  @behaviour Gust.Action

  alias Gust.Flows
  alias NetworkDefense.Evaluation.Comparison.Actions.Compare
  alias NetworkDefense.Evaluation.Comparison.TaskFailure.RetryableError

  @max_attempts 3
  @task_name "compare"

  @impl true
  def execute(args, %{run_id: run_id} = context) do
    Compare.execute(args, context)
  rescue
    error in RetryableError -> handle_retry(error, run_id, __STACKTRACE__)
  end

  defp handle_retry(error, run_id, stacktrace) do
    if current_prototype_attempt!(run_id) >= @max_attempts do
      raise Gust.DAG.NonRecError, Exception.message(error)
    else
      reraise error, stacktrace
    end
  end

  defp current_prototype_attempt!(run_id) do
    case Flows.get_tasks_by_name(@task_name, run_id) do
      [%{attempt: attempt}] -> attempt
      _tasks -> raise "the prototype DAG must contain exactly one compare task"
    end
  end
end
