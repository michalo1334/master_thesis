defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.PrepareReplica do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.{ItemStore, Planner}
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.IO

  # One replica of one tier.
  #
  # The canonical work of the replica comes from the stored definition, and the
  # item store answers with one stable row per declared position. A repeated
  # call reads the same rows, so the mapped tasks see the same identifiers.
  @spec run(IO.Replica.t()) :: {:ok, IO.Replica.t()} | {:error, StudyError.t()}
  def run(%IO.Replica{tier: tier, replica_position: position} = replica) do
    with {:ok, work} <-
           Planner.build_collection_work(
             tier.execution,
             tier.phase,
             tier.definition,
             position
           ),
         {:ok, tier_work} <- Planner.filter_tier(work, tier.definition, tier.tier),
         {:ok, items} <- prepare_items(tier.phase, position, tier_work) do
      {:ok, %{replica | items: items}}
    end
  end

  defp prepare_items(phase, replica_position, work) do
    work
    |> Enum.reduce_while({:ok, []}, fn work_item, {:ok, items} ->
      case ItemStore.get_or_create(phase.id, replica_position, work_item.item_position) do
        {:ok, item} ->
          prepared = %IO.Item{collection_item_id: item.id, collection_item: item}
          {:cont, {:ok, [prepared | items]}}

        {:error, %StudyError{} = error} ->
          {:halt, {:error, error}}
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
      step: NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.PrepareReplica

    alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.IO
    alias NetworkDefense.Evaluation.Study.Pipeline.GustAdapter

    @impl GustAdapter
    def decode(args, %{run_id: run_id}) when is_list(args) do
      with {:ok, position} <- Keyword.fetch(args, :replica_position),
           {:ok, tier} <- IO.load_tier_from_gust_run(run_id) do
        IO.Replica.for_tier(tier, position)
      end
    end

    @impl GustAdapter
    def encode(%IO.Replica{items: items}) do
      %{
        "gust_task_items" => Enum.map(items, &%{"collection_item_id" => &1.collection_item_id})
      }
    end
  end
end
