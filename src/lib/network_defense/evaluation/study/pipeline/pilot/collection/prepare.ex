defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.Prepare do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.ItemStore
  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.Planner
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.IO

  @replica_position 0

  @spec run(IO.t()) :: {:ok, IO.t()} | {:error, StudyError.t()}
  def run(%IO{} = io) do
    with {:ok, work} <-
           Planner.build_collection_work(
             io.execution,
             io.phase,
             io.definition,
             @replica_position
           ),
         {:ok, items} <- prepare_items(io.phase, work) do
      {:ok, %{io | work: work, items: items}}
    end
  end

  defp prepare_items(phase, work) do
    work
    |> Enum.reduce_while({:ok, []}, fn work_item, {:ok, items} ->
      case ItemStore.get_or_create(
             phase.id,
             @replica_position,
             work_item.item_position
           ) do
        {:ok, item} -> {:cont, {:ok, [%IO.Item{collection_item_id: item.id} | items]}}
        {:error, %StudyError{} = error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defmodule Gust do
    @moduledoc false

    use NetworkDefense.Evaluation.Study.Pipeline.GustAdapter,
      step: NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.Prepare

    alias NetworkDefense.Evaluation.Study.Pipeline.GustAdapter
    alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.IO

    @impl GustAdapter
    def decode(_args, %{run_id: run_id}), do: IO.load_from_gust_run(run_id)

    @impl GustAdapter
    def encode(%IO{items: items}) do
      %{
        "gust_task_items" => Enum.map(items, &%{"collection_item_id" => &1.collection_item_id})
      }
    end
  end
end
