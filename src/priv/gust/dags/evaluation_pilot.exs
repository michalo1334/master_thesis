defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.DAG do
  @moduledoc false
  use Gust.DSL, on_finished_callback: :notify_waiters
  use NetworkDefense.Evaluation.Study.Pipeline.GustCallback

  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.{EvaluateCandidate, Prepare, Select}

  # Fixed pilot DAG: declare, map one candidate comparison per canonical work
  # item, then select once from the complete set.
  #
  # `map_over` expands the saved preparation items. Gust runs `select_pilot`
  # only after every mapped comparison succeeds.

  task_action(:prepare_pilot, {Prepare.Gust, []},
    downstream: [:evaluate_candidate_comparison],
    store_result: true
  )

  task_action :evaluate_candidate_comparison, EvaluateCandidate.Gust,
    map_over: :prepare_pilot,
    ctx: %{params: params},
    downstream: [:select_pilot],
    store_result: true do
    [item: params]
  end

  task_action(:select_pilot, {Select.Gust, []}, store_result: true)
end
