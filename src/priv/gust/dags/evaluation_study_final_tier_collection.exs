defmodule NetworkDefense.Evaluation.Study.FinalTierCollectionDAG do
  @moduledoc false
  use Gust.DSL, on_finished_callback: :notify_waiters

  alias NetworkDefense.Evaluation.Study.GustRunNotifier

  alias NetworkDefense.Evaluation.Study.Actions.{
    CheckFinalEnvironment,
    CompleteFinalTier,
    MarkFinalTimingBoundary,
    PrepareFinalReplica,
    RunFinalPlanItem,
    RunFinalSimulationItem
  }

  def notify_waiters(_status, %{id: run_id}) do
    GustRunNotifier.notify(run_id)
  rescue
    _exception -> :ok
  catch
    _kind, _reason -> :ok
  end

  def notify_waiters(_status, _run), do: :ok

  # Static tasks read run parameters. Only mapped tasks receive item parameters.
  defp phase_run_id(run_id), do: Gust.Flows.get_run!(run_id).params["study_phase_run_id"]

  task_action :check_environment_before_warm_up, CheckFinalEnvironment,
    ctx: %{run_id: run_id},
    downstream: [:prepare_warm_up] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action :prepare_warm_up, PrepareFinalReplica,
    ctx: %{run_id: run_id},
    downstream: [:run_plan_warm_up],
    store_result: true do
    [study_phase_run_id: phase_run_id(run_id), replica_position: -1]
  end

  task_action :run_plan_warm_up, RunFinalPlanItem,
    map_over: :prepare_warm_up,
    ctx: %{params: params},
    downstream: [:run_simulation_warm_up] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :run_simulation_warm_up, RunFinalSimulationItem,
    map_over: :prepare_warm_up,
    ctx: %{params: params},
    downstream: [:check_environment_before_0] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :check_environment_before_0, CheckFinalEnvironment,
    ctx: %{run_id: run_id},
    downstream: [:prepare_0] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action :prepare_0, PrepareFinalReplica,
    ctx: %{run_id: run_id},
    downstream: [:mark_plan_dispatch_0],
    store_result: true do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 0]
  end

  task_action :mark_plan_dispatch_0, MarkFinalTimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_plan_0] do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 0, event_kind: :plan_dispatch]
  end

  task_action :run_plan_0, RunFinalPlanItem,
    map_over: :prepare_0,
    ctx: %{params: params},
    downstream: [:mark_plan_completion_0] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_plan_completion_0, MarkFinalTimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:mark_simulation_dispatch_0] do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 0, event_kind: :plan_completion]
  end

  task_action :mark_simulation_dispatch_0, MarkFinalTimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_simulation_0] do
    [
      study_phase_run_id: phase_run_id(run_id),
      replica_position: 0,
      event_kind: :simulation_dispatch
    ]
  end

  task_action :run_simulation_0, RunFinalSimulationItem,
    map_over: :prepare_0,
    ctx: %{params: params},
    downstream: [:mark_simulation_completion_0] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_simulation_completion_0, MarkFinalTimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:check_environment_after_0] do
    [
      study_phase_run_id: phase_run_id(run_id),
      replica_position: 0,
      event_kind: :simulation_completion
    ]
  end

  task_action :check_environment_after_0, CheckFinalEnvironment,
    ctx: %{run_id: run_id},
    downstream: [:check_environment_before_1] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action :check_environment_before_1, CheckFinalEnvironment,
    ctx: %{run_id: run_id},
    downstream: [:prepare_1] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action :prepare_1, PrepareFinalReplica,
    ctx: %{run_id: run_id},
    downstream: [:mark_plan_dispatch_1],
    store_result: true do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 1]
  end

  task_action :mark_plan_dispatch_1, MarkFinalTimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_plan_1] do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 1, event_kind: :plan_dispatch]
  end

  task_action :run_plan_1, RunFinalPlanItem,
    map_over: :prepare_1,
    ctx: %{params: params},
    downstream: [:mark_plan_completion_1] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_plan_completion_1, MarkFinalTimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:mark_simulation_dispatch_1] do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 1, event_kind: :plan_completion]
  end

  task_action :mark_simulation_dispatch_1, MarkFinalTimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_simulation_1] do
    [
      study_phase_run_id: phase_run_id(run_id),
      replica_position: 1,
      event_kind: :simulation_dispatch
    ]
  end

  task_action :run_simulation_1, RunFinalSimulationItem,
    map_over: :prepare_1,
    ctx: %{params: params},
    downstream: [:mark_simulation_completion_1] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_simulation_completion_1, MarkFinalTimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:check_environment_after_1] do
    [
      study_phase_run_id: phase_run_id(run_id),
      replica_position: 1,
      event_kind: :simulation_completion
    ]
  end

  task_action :check_environment_after_1, CheckFinalEnvironment,
    ctx: %{run_id: run_id},
    downstream: [:check_environment_before_2] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action :check_environment_before_2, CheckFinalEnvironment,
    ctx: %{run_id: run_id},
    downstream: [:prepare_2] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action :prepare_2, PrepareFinalReplica,
    ctx: %{run_id: run_id},
    downstream: [:mark_plan_dispatch_2],
    store_result: true do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 2]
  end

  task_action :mark_plan_dispatch_2, MarkFinalTimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_plan_2] do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 2, event_kind: :plan_dispatch]
  end

  task_action :run_plan_2, RunFinalPlanItem,
    map_over: :prepare_2,
    ctx: %{params: params},
    downstream: [:mark_plan_completion_2] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_plan_completion_2, MarkFinalTimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:mark_simulation_dispatch_2] do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 2, event_kind: :plan_completion]
  end

  task_action :mark_simulation_dispatch_2, MarkFinalTimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_simulation_2] do
    [
      study_phase_run_id: phase_run_id(run_id),
      replica_position: 2,
      event_kind: :simulation_dispatch
    ]
  end

  task_action :run_simulation_2, RunFinalSimulationItem,
    map_over: :prepare_2,
    ctx: %{params: params},
    downstream: [:mark_simulation_completion_2] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_simulation_completion_2, MarkFinalTimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:check_environment_after_2] do
    [
      study_phase_run_id: phase_run_id(run_id),
      replica_position: 2,
      event_kind: :simulation_completion
    ]
  end

  task_action :check_environment_after_2, CheckFinalEnvironment,
    ctx: %{run_id: run_id},
    downstream: [:check_environment_before_3] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action :check_environment_before_3, CheckFinalEnvironment,
    ctx: %{run_id: run_id},
    downstream: [:prepare_3] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action :prepare_3, PrepareFinalReplica,
    ctx: %{run_id: run_id},
    downstream: [:mark_plan_dispatch_3],
    store_result: true do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 3]
  end

  task_action :mark_plan_dispatch_3, MarkFinalTimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_plan_3] do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 3, event_kind: :plan_dispatch]
  end

  task_action :run_plan_3, RunFinalPlanItem,
    map_over: :prepare_3,
    ctx: %{params: params},
    downstream: [:mark_plan_completion_3] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_plan_completion_3, MarkFinalTimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:mark_simulation_dispatch_3] do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 3, event_kind: :plan_completion]
  end

  task_action :mark_simulation_dispatch_3, MarkFinalTimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_simulation_3] do
    [
      study_phase_run_id: phase_run_id(run_id),
      replica_position: 3,
      event_kind: :simulation_dispatch
    ]
  end

  task_action :run_simulation_3, RunFinalSimulationItem,
    map_over: :prepare_3,
    ctx: %{params: params},
    downstream: [:mark_simulation_completion_3] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_simulation_completion_3, MarkFinalTimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:check_environment_after_3] do
    [
      study_phase_run_id: phase_run_id(run_id),
      replica_position: 3,
      event_kind: :simulation_completion
    ]
  end

  task_action :check_environment_after_3, CheckFinalEnvironment,
    ctx: %{run_id: run_id},
    downstream: [:check_environment_before_4] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action :check_environment_before_4, CheckFinalEnvironment,
    ctx: %{run_id: run_id},
    downstream: [:prepare_4] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action :prepare_4, PrepareFinalReplica,
    ctx: %{run_id: run_id},
    downstream: [:mark_plan_dispatch_4],
    store_result: true do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 4]
  end

  task_action :mark_plan_dispatch_4, MarkFinalTimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_plan_4] do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 4, event_kind: :plan_dispatch]
  end

  task_action :run_plan_4, RunFinalPlanItem,
    map_over: :prepare_4,
    ctx: %{params: params},
    downstream: [:mark_plan_completion_4] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_plan_completion_4, MarkFinalTimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:mark_simulation_dispatch_4] do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 4, event_kind: :plan_completion]
  end

  task_action :mark_simulation_dispatch_4, MarkFinalTimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_simulation_4] do
    [
      study_phase_run_id: phase_run_id(run_id),
      replica_position: 4,
      event_kind: :simulation_dispatch
    ]
  end

  task_action :run_simulation_4, RunFinalSimulationItem,
    map_over: :prepare_4,
    ctx: %{params: params},
    downstream: [:mark_simulation_completion_4] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_simulation_completion_4, MarkFinalTimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:check_environment_after_4] do
    [
      study_phase_run_id: phase_run_id(run_id),
      replica_position: 4,
      event_kind: :simulation_completion
    ]
  end

  task_action :check_environment_after_4, CheckFinalEnvironment,
    ctx: %{run_id: run_id},
    downstream: [:complete_final_tier] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action(:complete_final_tier, {CompleteFinalTier, []}, store_result: true)
end
