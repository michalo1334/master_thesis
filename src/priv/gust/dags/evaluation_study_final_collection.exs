defmodule NetworkDefense.Evaluation.Study.FinalCollectionDAG do
  @moduledoc false
  use Gust.DSL, on_finished_callback: :notify_waiters

  alias NetworkDefense.Evaluation.Study.GustRunNotifier

  alias NetworkDefense.Evaluation.Study.Actions.{
    AssembleFinalSnapshot,
    CollectItem,
    PrepareFinalCollection
  }

  def notify_waiters(_status, %{id: run_id}) do
    GustRunNotifier.notify(run_id)
  rescue
    _exception -> :ok
  catch
    _kind, _reason -> :ok
  end

  def notify_waiters(_status, _run), do: :ok

  task_action(:prepare_final_collection, {PrepareFinalCollection, []},
    downstream: [:collect_final_item],
    store_result: true
  )

  task_action :collect_final_item, CollectItem,
    map_over: :prepare_final_collection,
    ctx: %{params: params},
    downstream: [:assemble_final_snapshot],
    store_result: true do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action(:assemble_final_snapshot, {AssembleFinalSnapshot, []}, store_result: true)
end
