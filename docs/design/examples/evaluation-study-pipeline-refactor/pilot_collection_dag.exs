defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.DAG do
  @moduledoc false

  use Gust.DSL, on_finished_callback: :notify_waiters
  use NetworkDefense.Evaluation.Study.Pipeline.GustCallback

  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.{
    Assemble,
    Collect,
    Prepare
  }

  task_action :prepare_collection, Prepare.Gust,
    downstream: [:collect_item],
    store_result: true

  task_action :collect_item, Collect.Gust,
    map_over: :prepare_collection,
    ctx: %{params: params},
    downstream: [:assemble_snapshot],
    store_result: true do
    [item: params]
  end

  task_action :assemble_snapshot, Assemble.Gust, store_result: true
end
