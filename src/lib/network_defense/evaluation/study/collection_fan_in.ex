defmodule NetworkDefense.Evaluation.Study.CollectionFanIn do
  @moduledoc false

  import Ecto.Query

  alias NetworkDefense.Evaluation.Study.Contracts.{CollectionResult, CollectionWorkItem}
  alias NetworkDefense.Evaluation.{StudyCollectionItem, StudyPhase}
  alias NetworkDefense.Repo

  @replica_position 0

  @spec load_items(
          StudyPhase.t(),
          [CollectionWorkItem.t()],
          pos_integer(),
          String.t(),
          String.t()
        ) ::
          {:ok, [StudyCollectionItem.t()]} | :error
  def load_items(phase, work, run_id, prepare_task, collection_task) do
    with {:ok, items, payloads} <- authoritative_items(phase, work),
         :ok <- validate_preparation(run_id, payloads, prepare_task),
         :ok <- validate_mapped_tasks(run_id, payloads, items, collection_task) do
      {:ok, items}
    end
  end

  defp authoritative_items(%StudyPhase{id: phase_id}, work) do
    items =
      Repo.all(
        from item in StudyCollectionItem,
          where:
            item.study_phase_id == ^phase_id and
              item.replica_position == @replica_position,
          order_by: item.item_position
      )

    expected_positions = Enum.map(work, & &1.item_position)

    if Enum.map(items, & &1.item_position) == expected_positions do
      payloads = Enum.map(items, &%{"collection_item_id" => &1.id})
      {:ok, items, payloads}
    else
      :error
    end
  end

  defp validate_preparation(run_id, payloads, prepare_task) do
    case Gust.Flows.get_tasks_by_name(prepare_task, run_id) do
      [%{status: :succeeded, result: %{"gust_task_items" => ^payloads}}] -> :ok
      _missing_or_changed -> :error
    end
  end

  defp validate_mapped_tasks(run_id, payloads, items, collection_task) do
    tasks = Gust.Flows.get_tasks_by_name(collection_task, run_id)

    expected_indices =
      case length(payloads) do
        0 -> []
        count -> Enum.to_list(0..(count - 1))
      end

    if length(tasks) == length(payloads) and Enum.map(tasks, & &1.map_index) == expected_indices do
      tasks
      |> Enum.zip(payloads)
      |> Enum.zip(items)
      |> Enum.reduce_while(:ok, &validate_mapped_task/2)
    else
      :error
    end
  end

  defp validate_mapped_task({{task, payload}, item}, :ok) do
    case validate_task(task, payload, item) do
      :ok -> {:cont, :ok}
      :error -> {:halt, :error}
    end
  end

  defp validate_task(
         %{status: :succeeded, params: payload, result: result},
         payload,
         %StudyCollectionItem{} = item
       )
       when is_map(result) do
    case CollectionResult.new(result) do
      {:ok, receipt}
      when receipt.collection_item_id == item.id and
             receipt.replica_position == item.replica_position and
             receipt.item_position == item.item_position ->
        :ok

      _invalid ->
        :error
    end
  end

  defp validate_task(_task, _payload, _item), do: :error
end
