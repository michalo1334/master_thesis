defmodule NetworkDefense.Evaluation.Final.Collector do
  @moduledoc false

  alias NetworkDefense.Evaluation.Family.Contracts.Identity

  alias NetworkDefense.Evaluation.Final.Contracts.{
    FinalError,
    Request,
    SnapshotPayload
  }

  alias NetworkDefense.Evaluation.Final.Member

  # Fan-in validation for the complete declared Final family.
  #
  # Collection reads persisted Gust records. It never trusts task completion
  # order: mapped results are matched by `map_index` and by typed identity.
  #
  # The submitted Final request is the only authority for what a member must
  # contain. Persisted items stay compact, so the check covers the declared
  # position, the declared identity, and the successful status. The comparison
  # request itself is rebuilt from the stored snapshot and the submitted seed.

  @prepare_task "prepare_final"
  @member_task "compare_final_member"

  @type member :: %{
          identity: Identity.t(),
          request: NetworkDefense.Evaluation.Comparison.Contracts.ComparisonRequest.t(),
          statistics: NetworkDefense.Evaluation.Comparison.Contracts.ComparisonStatistics.t()
        }

  @spec collect(integer(), Request.t(), SnapshotPayload.t()) ::
          {:ok, [member()]} | {:error, FinalError.t()}
  def collect(run_id, %Request{} = request, %SnapshotPayload{} = payload) do
    with :ok <- validate_prepared(run_id, request),
         {:ok, tasks} <- mapped_tasks(run_id, request),
         :ok <- validate_indices(tasks),
         {:ok, members} <- parse_tasks(tasks, request, payload),
         :ok <- validate_unique(members) do
      {:ok, members}
    end
  end

  defp validate_prepared(run_id, %Request{} = request) do
    with {:ok, items} <- prepared_items(run_id) do
      expected = Member.declared_items(request)

      if items == expected do
        :ok
      else
        {:error,
         FinalError.incomplete_family(
           "The persisted Final preparation does not match the declared family."
         )}
      end
    end
  end

  defp prepared_items(run_id) do
    case Gust.Flows.get_tasks_by_name(@prepare_task, run_id) do
      [%{result: %{"gust_task_items" => items}}] when is_list(items) ->
        {:ok, items}

      _missing_or_malformed ->
        {:error,
         FinalError.incomplete_family("The persisted Final preparation is missing or malformed.")}
    end
  end

  defp mapped_tasks(run_id, %Request{} = request) do
    expected_size = length(request.expected_comparisons)

    case Gust.Flows.get_tasks_by_name(@member_task, run_id) do
      [] ->
        {:error, FinalError.incomplete_family("The Final family has no mapped comparison tasks.")}

      tasks ->
        if Enum.count(tasks) == expected_size do
          {:ok, Enum.sort_by(tasks, & &1.map_index)}
        else
          {:error,
           FinalError.incomplete_family(
             "The mapped comparison task count does not equal the declared Final family size."
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
       FinalError.incomplete_family(
         "Mapped comparison task indices must be zero-based and match declared positions."
       )}
    end
  end

  defp parse_tasks(tasks, %Request{} = request, %SnapshotPayload{} = payload) do
    tasks
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {task, index}, {:ok, acc} ->
      case parse_task(task, request, payload, index) do
        {:ok, member} -> {:cont, {:ok, [member | acc]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, members} -> {:ok, Enum.reverse(members)}
      {:error, error} -> {:error, error}
    end
  end

  defp parse_task(task, %Request{} = request, payload, index) do
    declared = Enum.at(request.expected_comparisons, index)

    with :ok <- check_status(task),
         {:ok, item} <- Member.parse_item(task.params),
         :ok <- check_position(item, index),
         :ok <- check_identity(item.identity, declared),
         {:ok, comparison_request} <- Member.comparison_request(request, payload, index),
         {:ok, result} <- Member.parse_result(task.result, comparison_request),
         :ok <- check_identity(result.identity, item.identity) do
      {:ok,
       %{identity: item.identity, request: comparison_request, statistics: result.statistics}}
    end
  end

  defp check_status(%{status: :succeeded}), do: :ok

  defp check_status(_task),
    do: {:error, FinalError.incomplete_family("Every mapped comparison task must succeed.")}

  defp check_position(%{position: position}, index) do
    if position == index do
      :ok
    else
      {:error,
       FinalError.changed_member(
         "A mapped Final comparison is not stored at its declared position."
       )}
    end
  end

  defp check_identity(%Identity{} = actual, %Identity{} = expected) do
    if Identity.matches?(actual, expected) do
      :ok
    else
      {:error,
       FinalError.changed_member(
         "A mapped Final comparison identity does not match its declared position."
       )}
    end
  end

  defp check_identity(_actual, _expected),
    do: {:error, FinalError.incomplete_family("A declared Final identity is missing.")}

  defp validate_unique(members) do
    keys = Enum.map(members, &Identity.key(&1.identity))

    if length(keys) == length(Enum.uniq(keys)) do
      :ok
    else
      {:error, FinalError.incomplete_family("Mapped Final comparison identities must be unique.")}
    end
  end
end
