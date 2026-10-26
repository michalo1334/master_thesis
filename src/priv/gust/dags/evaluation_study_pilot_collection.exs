defmodule NetworkDefense.Evaluation.Study.PilotCollectionDAG do
  @moduledoc false
  use Gust.DSL, on_finished_callback: :notify_waiters

  alias NetworkDefense.Evaluation.Study.GustRunNotifier

  alias NetworkDefense.Evaluation.Study.Actions.{
    AssemblePilotSnapshot,
    CollectItem,
    PreparePilotCollection
  }

  def notify_waiters(_status, %{id: run_id}) do
    GustRunNotifier.notify(run_id)
  rescue
    _exception -> :ok
  catch
    _kind, _reason -> :ok
  end

  def notify_waiters(_status, _run), do: :ok

  task_action(:prepare_pilot_collection, {PreparePilotCollection, []},
    downstream: [:collect_pilot_item],
    store_result: true
  )

  task_action :collect_pilot_item, CollectItem,
    map_over: :prepare_pilot_collection,
    ctx: %{params: params},
    downstream: [:assemble_pilot_snapshot],
    store_result: true do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action(:assemble_pilot_snapshot, {AssemblePilotSnapshot, []}, store_result: true)
end
