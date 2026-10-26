defmodule NetworkDefense.Evaluation.Final.Workflow do
  @moduledoc false

  alias Gust.DAG.Run.Trigger

  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonError
  alias NetworkDefense.Evaluation.Comparison.TaskFailure, as: ComparisonTaskFailure
  alias NetworkDefense.Evaluation.Final.Binding
  alias NetworkDefense.Evaluation.Final.Collector
  alias NetworkDefense.Evaluation.Final.Contracts.{FinalError, Request, Result}
  alias NetworkDefense.Evaluation.Final.{Limits, Member, TaskFailure, Wire}
  alias NetworkDefense.Evaluation.Study.GustWaiter

  # Separate Final workflow.
  #
  # The single-comparison and family workflows must not guess which result
  # shape a run contains, so this module owns Final submission, waiting, and
  # read-back. Waiting never returns the result.

  @dag_name "evaluation_final"
  @correct_task "correct_final_family"

  @spec create(map()) :: {:ok, integer()} | {:error, FinalError.t()}
  def create(request_map) do
    with {:ok, %Request{} = request} <- Request.parse(request_map),
         :ok <- Limits.validate(request),
         {:ok, payload} <- Binding.verify(request, limits: false),
         :ok <- Member.preflight(request, payload),
         %{id: dag_id} <- Gust.Flows.get_dag_by_name(@dag_name),
         {:ok, run} <- Gust.Flows.create_run(%{dag_id: dag_id, params: Wire.request(request)}) do
      {:ok, run.id}
    else
      {:error, %FinalError{} = error} -> {:error, error}
      _error -> {:error, workflow_error()}
    end
  rescue
    _exception in [Postgrex.Error, DBConnection.ConnectionError] -> {:error, workflow_error()}
  end

  @spec dispatch(integer()) :: :ok | {:error, FinalError.t()}
  def dispatch(run_id) do
    run = Gust.Flows.get_run!(run_id)
    _dispatched = Trigger.dispatch_run(run)
    :ok
  rescue
    _exception in [Postgrex.Error, DBConnection.ConnectionError] -> {:error, workflow_error()}
  end

  @spec submit(map()) :: {:ok, integer()} | {:error, FinalError.t()}
  def submit(request_map) do
    with {:ok, run_id} <- create(request_map),
         :ok <- dispatch(run_id) do
      {:ok, run_id}
    end
  end

  @spec await(integer(), timeout()) ::
          {:ok, :succeeded} | {:error, :timeout | :not_found | FinalError.t()}
  def await(run_id, timeout \\ :infinity) do
    with {:ok, run_id} <- valid_run_id(run_id),
         {:ok, timeout} <- valid_timeout(timeout) do
      await_persisted(run_id, timeout)
    end
  rescue
    _exception in [Postgrex.Error, DBConnection.ConnectionError] -> {:error, workflow_error()}
  end

  @spec result(integer()) ::
          {:ok, Result.t()} | {:error, :not_found | :not_ready | FinalError.t()}
  def result(run_id) do
    with {:ok, run_id} <- valid_run_id(run_id) do
      stored_result_for(run_id)
    end
  rescue
    _exception in [Postgrex.Error, DBConnection.ConnectionError] -> {:error, workflow_error()}
  end

  # Read-back repeats the snapshot metadata, byte count, declared order, and
  # source Pilot binding. Result read performs no compute, so the resource guard
  # stays out of this boundary. A snapshot or Pilot that changed after success
  # therefore makes the stored result unreadable instead of silently returning
  # an outdated study or family binding.
  defp stored_result_for(run_id) do
    case fetch_run(run_id) do
      nil ->
        {:error, :not_found}

      %{status: :succeeded, params: params} ->
        with {:ok, request} <- Request.parse(params),
             {:ok, payload} <- Binding.verify(request, limits: false),
             {:ok, members} <- Collector.collect(run_id, request, payload),
             {:ok, stored} <- stored_result(run_id) do
          Result.parse(stored, request, members)
        end

      %{status: :failed} ->
        {:error, failure_for_run(run_id)}

      _active_run ->
        {:error, :not_ready}
    end
  end

  defp valid_run_id(run_id) when is_integer(run_id) and run_id > 0, do: {:ok, run_id}

  defp valid_run_id(_run_id),
    do: {:error, FinalError.invalid_argument("The Final run ID must be a positive integer.")}

  defp valid_timeout(:infinity), do: {:ok, :infinity}

  defp valid_timeout(timeout_ms) when is_integer(timeout_ms) and timeout_ms >= 0,
    do: {:ok, timeout_ms}

  defp valid_timeout(_timeout_ms),
    do:
      {:error,
       FinalError.invalid_argument("The timeout must be a non-negative integer of milliseconds.")}

  @spec failure_for_run(integer()) :: FinalError.t()
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
    _exception in [Postgrex.Error, DBConnection.ConnectionError] -> workflow_error()
  end

  defp await_persisted(run_id, timeout) do
    case GustWaiter.await(run_id, timeout) do
      {:ok, :succeeded} -> {:ok, :succeeded}
      {:error, :failed} -> {:error, failure_for_run(run_id)}
      {:error, :not_found} -> {:error, :not_found}
      {:error, :timeout} -> {:error, :timeout}
      {:error, :unavailable} -> {:error, FinalError.unavailable()}
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

  # A failed Final run can fail in two ways. A Final task stores a Final error.
  # A mapped member task stores the accepted comparison error. Both envelopes
  # are tagged, so the decoder never guesses which shape it has.
  defp decode_task_error(error) do
    case TaskFailure.decode(error) do
      {:ok, final_error} ->
        final_error

      :error ->
        case ComparisonTaskFailure.decode(error) do
          {:ok, %ComparisonError{} = comparison_error} ->
            FinalError.from_foreign(comparison_error)

          :error ->
            workflow_error()
        end
    end
  end

  defp invalid_result_error, do: FinalError.invalid_result("The stored Final result is invalid.")
  defp workflow_error, do: FinalError.workflow_failed()
end
