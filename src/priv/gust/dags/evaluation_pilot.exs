defmodule NetworkDefense.Evaluation.Pilot.DAG do
  @moduledoc false
  use Gust.DSL, on_finished_callback: :notify_waiters

  alias NetworkDefense.Evaluation.Study.GustRunNotifier

  alias NetworkDefense.Evaluation.Pilot.Actions.{
    EvaluateCandidateComparison,
    Prepare,
    Select
  }

  def notify_waiters(_status, %{id: run_id}) do
    GustRunNotifier.notify(run_id)
  rescue
    _exception -> :ok
  catch
    _kind, _reason -> :ok
  end

  def notify_waiters(_status, _run), do: :ok

  # Fixed pilot DAG: declare, map one candidate comparison per canonical work
  # item, then select once from the complete set.
  #
  # `map_over` expands the saved preparation items. Gust runs `select_pilot`
  # only after every mapped comparison succeeds.

  task_action(:prepare_pilot, {Prepare, []},
    downstream: [:evaluate_candidate_comparison],
    store_result: true
  )

  task_action :evaluate_candidate_comparison, EvaluateCandidateComparison,
    map_over: :prepare_pilot,
    ctx: %{params: params},
    downstream: [:select_pilot],
    store_result: true do
    [item: params]
  end

  task_action(:select_pilot, {Select, []}, store_result: true)
end
