defmodule NetworkDefense.Evaluation.Final.DAG do
  @moduledoc false
  use Gust.DSL, on_finished_callback: :notify_waiters

  alias NetworkDefense.Evaluation.Final.Actions.{
    CompareFinalMember,
    CorrectFinalFamily,
    PrepareFinal
  }

  alias NetworkDefense.Evaluation.Study.GustRunNotifier

  def notify_waiters(_status, %{id: run_id}) do
    GustRunNotifier.notify(run_id)
  rescue
    _exception -> :ok
  catch
    _kind, _reason -> :ok
  end

  def notify_waiters(_status, _run), do: :ok

  # Fixed Final DAG: validate, map one member per declared identity, then correct
  # the complete family once.
  #
  # `map_over` expands the saved preparation items. Gust runs
  # `correct_final_family` only after every mapped member succeeds. The Final
  # DAG contains no nested comparison, family, or pilot run: it reuses the
  # accepted comparison action and the accepted correction call directly.

  task_action(:prepare_final, {PrepareFinal, []},
    downstream: [:compare_final_member],
    store_result: true
  )

  task_action :compare_final_member, CompareFinalMember,
    map_over: :prepare_final,
    ctx: %{params: params},
    downstream: [:correct_final_family],
    store_result: true do
    [item: params]
  end

  task_action(:correct_final_family, {CorrectFinalFamily, []}, store_result: true)
end
