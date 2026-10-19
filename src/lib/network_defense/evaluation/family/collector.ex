defmodule NetworkDefense.Evaluation.Family.Collector do
  @moduledoc false

  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonRequest
  alias NetworkDefense.Evaluation.Family.Contracts.{FamilyError, FamilyRequest, Identity}
  alias NetworkDefense.Evaluation.Family.Member

  # Fan-in validation for the complete declared family.
  #
  # Collection reads persisted Gust records. It never trusts task completion
  # order: mapped results are matched by `map_index` and by typed identity.
  #
  # The submitted root request is the only authority for what a member must
  # contain. Both the persisted preparation and the persisted mapped inputs
  # must equal the root item at their declared position, so a changed seed or a
  # changed analysis setting stops the run before the Holm call.

  @prepare_task "prepare_family"
  @member_task "compare_member"

  @type expected :: %{
          identity: Identity.t(),
          request: ComparisonRequest.t(),
          params: map()
        }

  @type member :: %{
          identity: Identity.t(),
          request: ComparisonRequest.t(),
          statistics: NetworkDefense.Evaluation.Comparison.Contracts.ComparisonStatistics.t()
        }

  @spec collect(integer(), FamilyRequest.t()) :: {:ok, [member()]} | {:error, FamilyError.t()}
  def collect(run_id, %FamilyRequest{} = request) do
    with {:ok, expected} <- expected_items(request),
         :ok <- validate_prepared(run_id, expected),
         {:ok, tasks} <- mapped_tasks(run_id, expected),
         :ok <- validate_indices(tasks),
         {:ok, members} <- parse_tasks(tasks, expected),
         :ok <- validate_unique(members) do
      {:ok, members}
    end
  end

  defp expected_items(%FamilyRequest{} = request) do
    with {:ok, items} <- Member.canonical_items(request) do
      parse_items(items)
    end
  end

  defp parse_items(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn params, {:ok, acc} ->
      case Member.parse_input(params) do
        {:ok, input} -> {:cont, {:ok, [Map.put(input, :params, params) | acc]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      {:error, error} -> {:error, error}
    end
  end

  defp validate_prepared(run_id, expected) do
    with {:ok, items} <- prepared_items(run_id) do
      if length(items) == length(expected) do
        agree(items, expected)
      else
        {:error,
         FamilyError.incomplete_family(
           "The persisted family preparation does not match the declared family size."
         )}
      end
    end
  end

  defp agree(items, expected) do
    items
    |> Enum.zip(expected)
    |> Enum.reduce_while(:ok, fn pair, :ok -> agree_pair(pair) end)
  end

  defp agree_pair({item, want}) do
    with {:ok, input} <- Member.parse_input(item),
         :ok <- check_agreement(input, want) do
      {:cont, :ok}
    else
      {:error, error} -> {:halt, {:error, error}}
    end
  end

  defp prepared_items(run_id) do
    case Gust.Flows.get_tasks_by_name(@prepare_task, run_id) do
      [%{result: %{"gust_task_items" => items}}] when is_list(items) ->
        {:ok, items}

      _missing_or_malformed ->
        {:error,
         FamilyError.incomplete_family(
           "The persisted family preparation is missing or malformed."
         )}
    end
  end

  defp mapped_tasks(run_id, expected) do
    expected_size = length(expected)

    case Gust.Flows.get_tasks_by_name(@member_task, run_id) do
      [] ->
        {:error, FamilyError.incomplete_family("The family has no mapped comparison tasks.")}

      tasks ->
        if Enum.count(tasks) == expected_size do
          {:ok, tasks}
        else
          {:error,
           FamilyError.incomplete_family(
             "The mapped comparison task count does not equal the declared family size."
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
       FamilyError.incomplete_family(
         "Mapped comparison task indices must be zero-based and match declared positions."
       )}
    end
  end

  defp parse_tasks(tasks, expected) do
    tasks
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {task, index}, {:ok, acc} ->
      case parse_task(task, Enum.at(expected, index)) do
        {:ok, member} -> {:cont, {:ok, [member | acc]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, members} -> {:ok, Enum.reverse(members)}
      {:error, error} -> {:error, error}
    end
  end

  defp parse_task(task, %{identity: expected_identity, request: request} = want) do
    with :ok <- check_status(task),
         {:ok, input} <- Member.parse_input(task.params),
         :ok <- check_agreement(input, want),
         :ok <- check_identity(input.identity, expected_identity),
         {:ok, result} <- Member.parse_result(task.result, request),
         :ok <- check_identity(result.identity, input.identity) do
      {:ok, %{identity: input.identity, request: request, statistics: result.statistics}}
    end
  end

  # Persisted parameters must equal the submitted root item. Equality uses the
  # canonical maps, so JSON object order cannot change the answer.
  defp check_agreement(%{identity: identity, request: request}, want) do
    actual = %{
      "identity" => Identity.to_params(identity),
      "request" => ComparisonRequest.to_params(request)
    }

    cond do
      not Identity.matches?(identity, want.identity) ->
        {:error,
         FamilyError.changed_member(
           "A persisted family member identity does not match its declared position."
         )}

      actual != want.params ->
        {:error,
         FamilyError.changed_member(
           "A persisted family member request does not match the submitted comparison request."
         )}

      true ->
        :ok
    end
  end

  defp check_status(%{status: :succeeded}), do: :ok

  defp check_status(_task),
    do: {:error, FamilyError.incomplete_family("Every mapped comparison task must succeed.")}

  defp check_identity(%Identity{} = actual, %Identity{} = expected) do
    if Identity.matches?(actual, expected) do
      :ok
    else
      {:error,
       FamilyError.incomplete_family(
         "A mapped comparison result does not keep its declared identity."
       )}
    end
  end

  defp validate_unique(members) do
    keys = Enum.map(members, &Identity.key(&1.identity))

    if length(keys) == length(Enum.uniq(keys)) do
      :ok
    else
      {:error, FamilyError.incomplete_family("Mapped comparison identities must be unique.")}
    end
  end
end
