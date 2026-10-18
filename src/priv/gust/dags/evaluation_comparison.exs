defmodule NetworkDefense.Evaluation.Comparison.DAG do
  @moduledoc false
  use Gust.DSL

  alias NetworkDefense.Evaluation.Comparison.Actions.{Prepare, PrototypeCompare}

  task_action :prepare, {Prepare, []}, downstream: [:compare]

  task_action :compare, PrototypeCompare,
    ctx: %{run_id: run_id},
    store_result: true do
    request = Gust.Flows.get_run!(run_id).params
    [request: request]
  end
end
