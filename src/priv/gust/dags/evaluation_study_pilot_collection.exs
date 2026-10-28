defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.DAG do
  @moduledoc false

  use Gust.DSL, on_finished_callback: :notify_waiters
  use NetworkDefense.Evaluation.Study.Pipeline.GustCallback

  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.{Assemble, Collect, Prepare}

  # Fixed Pilot collection DAG: plan the work once, map one collection item per
  # stable row, then assemble one snapshot from the authoritative fan-in.

  task_action(:prepare_pilot_collection, {Prepare.Gust, []},
    downstream: [:collect_pilot_item],
    store_result: true
  )

  task_action :collect_pilot_item, Collect.Gust,
    map_over: :prepare_pilot_collection,
    ctx: %{params: params},
    downstream: [:assemble_pilot_snapshot],
    store_result: true do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action(:assemble_pilot_snapshot, {Assemble.Gust, []}, store_result: true)
end
