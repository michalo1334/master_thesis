defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.DAG do
  @moduledoc false
  use Gust.DSL, on_finished_callback: :notify_waiters
  use NetworkDefense.Evaluation.Study.Pipeline.GustCallback

  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.{
    CompareMember,
    CorrectFamily,
    Prepare
  }

  # Fixed Final DAG: validate, map one member per declared identity, then correct
  # the complete family once.
  #
  # `map_over` expands the saved preparation items. Gust runs
  # `correct_final_family` only after every mapped member succeeds. The Final
  # DAG contains no nested comparison, family, or pilot run: it reuses the
  # accepted comparison action and the accepted correction call directly.

  task_action(:prepare_final, {Prepare, []},
    downstream: [:compare_final_member],
    store_result: true
  )

  task_action :compare_final_member, CompareMember,
    map_over: :prepare_final,
    ctx: %{params: params},
    downstream: [:correct_final_family],
    store_result: true do
    [item: params]
  end

  task_action(:correct_final_family, {CorrectFamily, []}, store_result: true)
end
