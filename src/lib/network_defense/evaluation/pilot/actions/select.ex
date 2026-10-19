defmodule NetworkDefense.Evaluation.Pilot.Actions.Select do
  @moduledoc false
  @behaviour Gust.Action

  alias NetworkDefense.Evaluation.EvidenceSnapshots

  alias NetworkDefense.Evaluation.Pilot.Contracts.{
    CandidateComparisonResult,
    PilotError,
    PilotRequest
  }

  alias NetworkDefense.Evaluation.Pilot.{Assembler, TaskFailure, Wire, Work}

  # Fan-in task.
  #
  # It verifies the persisted preparation, every mapped item, and every
  # persisted row. It then assembles one typed result and recomputes every
  # aggregate before the result is stored.

  @prepare_task "prepare_pilot"
  @candidate_task "evaluate_candidate_comparison"

  @impl true
  def execute(_args, %{run_id: run_id}) do
    with {:ok, request} <- load_request(run_id),
         {:ok, snapshot, payload} <- EvidenceSnapshots.load(request.snapshot_id),
         :ok <- PilotRequest.matches_snapshot(request, snapshot, payload),
         {:ok, items} <- Work.canonical_items(request, payload),
         :ok <- validate_prepared(run_id, items),
         {:ok, tasks} <- mapped_tasks(run_id, items),
         :ok <- validate_indices(tasks),
         {:ok, results} <- parse_tasks(tasks, items, request, payload),
         {:ok, result} <- Assembler.assemble(request, payload, results) do
      Wire.result(result)
    else
      {:error, %PilotError{} = error} -> TaskFailure.raise_permanent(error)
    end
  end

  defp load_request(run_id) do
    run_id
    |> Gust.Flows.get_run!()
    |> Map.fetch!(:params)
    |> PilotRequest.parse()
  end

  defp validate_prepared(run_id, items) do
    case Gust.Flows.get_tasks_by_name(@prepare_task, run_id) do
      [%{result: %{"gust_task_items" => prepared}}] when is_list(prepared) ->
        if prepared == items do
          :ok
        else
          {:error, PilotError.incomplete_pilot("The persisted pilot preparation changed.")}
        end

      _missing_or_malformed ->
        {:error, PilotError.incomplete_pilot("The persisted pilot preparation is missing.")}
    end
  end

  defp mapped_tasks(run_id, items) do
    case Gust.Flows.get_tasks_by_name(@candidate_task, run_id) do
      [] ->
        {:error, PilotError.incomplete_pilot("The pilot has no mapped candidate tasks.")}

      tasks ->
        if length(tasks) == length(items) do
          {:ok, tasks}
        else
          {:error,
           PilotError.incomplete_pilot(
             "The mapped candidate task count does not equal the declared pilot size."
           )}
        end
    end
  end

  defp validate_indices(tasks) do
    indices = Enum.map(tasks, & &1.map_index)

    if indices == Enum.to_list(0..(length(tasks) - 1)) do
      :ok
    else
      {:error,
       PilotError.incomplete_pilot(
         "Mapped candidate task indices must be zero-based and match declared positions."
       )}
    end
  end

  defp parse_tasks(tasks, items, request, payload) do
    tasks
    |> Enum.zip(items)
    |> Enum.reduce_while({:ok, []}, fn {task, item}, {:ok, acc} ->
      case parse_task(task, item, request, payload) do
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      {:error, error} -> {:error, error}
    end
  end

  defp parse_task(%{status: :succeeded, params: params, result: result}, item, request, payload) do
    if params == item do
      parse_result(result, item, request, payload)
    else
      {:error, PilotError.changed_candidate_result("A mapped candidate task changed.")}
    end
  end

  defp parse_task(_task, _item, _request, _payload) do
    {:error, PilotError.incomplete_pilot("A mapped candidate task did not succeed.")}
  end

  defp parse_result(result, item, request, payload) when is_map(result) do
    with {:ok, candidate_request} <- Work.candidate_request(request, payload, item) do
      parse_row(result, candidate_request)
    end
  end

  defp parse_result(_result, _item, _request, _payload) do
    {:error, PilotError.incomplete_pilot("A mapped candidate task stored no result.")}
  end

  defp parse_row(result, candidate_request) do
    case CandidateComparisonResult.parse_row(result, candidate_request) do
      {:ok, parsed} ->
        {:ok, parsed}

      {:error, %PilotError{issues: [_ | _]} = error} ->
        {:error, error}

      {:error, _schema_failure} ->
        {:error, PilotError.invalid_result("A mapped candidate result is invalid.")}
    end
  end
end
