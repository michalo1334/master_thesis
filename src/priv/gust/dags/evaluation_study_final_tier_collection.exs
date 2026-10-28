defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.DAG do
  @moduledoc false
  use Gust.DSL, on_finished_callback: :notify_waiters
  use NetworkDefense.Evaluation.Study.Pipeline.GustCallback

  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.EnvironmentBoundary
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.CompleteTier
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.TimingBoundary
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.PrepareReplica
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.RunPlan
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.RunSimulation

  # Static tasks read run parameters. Only mapped tasks receive item parameters.
  defp phase_run_id(run_id), do: Gust.Flows.get_run!(run_id).params["study_phase_run_id"]

  task_action :check_environment_before_warm_up, EnvironmentBoundary,
    ctx: %{run_id: run_id},
    downstream: [:prepare_warm_up] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action :prepare_warm_up, PrepareReplica,
    ctx: %{run_id: run_id},
    downstream: [:run_plan_warm_up],
    store_result: true do
    [study_phase_run_id: phase_run_id(run_id), replica_position: -1]
  end

  task_action :run_plan_warm_up, RunPlan,
    map_over: :prepare_warm_up,
    ctx: %{params: params},
    downstream: [:run_simulation_warm_up] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :run_simulation_warm_up, RunSimulation,
    map_over: :prepare_warm_up,
    ctx: %{params: params},
    downstream: [:check_environment_before_0] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :check_environment_before_0, EnvironmentBoundary,
    ctx: %{run_id: run_id},
    downstream: [:prepare_0] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action :prepare_0, PrepareReplica,
    ctx: %{run_id: run_id},
    downstream: [:mark_plan_dispatch_0],
    store_result: true do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 0]
  end

  task_action :mark_plan_dispatch_0, TimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_plan_0] do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 0, event_kind: :plan_dispatch]
  end

  task_action :run_plan_0, RunPlan,
    map_over: :prepare_0,
    ctx: %{params: params},
    downstream: [:mark_plan_completion_0] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_plan_completion_0, TimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:mark_simulation_dispatch_0] do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 0, event_kind: :plan_completion]
  end

  task_action :mark_simulation_dispatch_0, TimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_simulation_0] do
    [
      study_phase_run_id: phase_run_id(run_id),
      replica_position: 0,
      event_kind: :simulation_dispatch
    ]
  end

  task_action :run_simulation_0, RunSimulation,
    map_over: :prepare_0,
    ctx: %{params: params},
    downstream: [:mark_simulation_completion_0] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_simulation_completion_0, TimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:check_environment_after_0] do
    [
      study_phase_run_id: phase_run_id(run_id),
      replica_position: 0,
      event_kind: :simulation_completion
    ]
  end

  task_action :check_environment_after_0, EnvironmentBoundary,
    ctx: %{run_id: run_id},
    downstream: [:check_environment_before_1] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action :check_environment_before_1, EnvironmentBoundary,
    ctx: %{run_id: run_id},
    downstream: [:prepare_1] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action :prepare_1, PrepareReplica,
    ctx: %{run_id: run_id},
    downstream: [:mark_plan_dispatch_1],
    store_result: true do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 1]
  end

  task_action :mark_plan_dispatch_1, TimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_plan_1] do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 1, event_kind: :plan_dispatch]
  end

  task_action :run_plan_1, RunPlan,
    map_over: :prepare_1,
    ctx: %{params: params},
    downstream: [:mark_plan_completion_1] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_plan_completion_1, TimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:mark_simulation_dispatch_1] do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 1, event_kind: :plan_completion]
  end

  task_action :mark_simulation_dispatch_1, TimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_simulation_1] do
    [
      study_phase_run_id: phase_run_id(run_id),
      replica_position: 1,
      event_kind: :simulation_dispatch
    ]
  end

  task_action :run_simulation_1, RunSimulation,
    map_over: :prepare_1,
    ctx: %{params: params},
    downstream: [:mark_simulation_completion_1] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_simulation_completion_1, TimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:check_environment_after_1] do
    [
      study_phase_run_id: phase_run_id(run_id),
      replica_position: 1,
      event_kind: :simulation_completion
    ]
  end

  task_action :check_environment_after_1, EnvironmentBoundary,
    ctx: %{run_id: run_id},
    downstream: [:check_environment_before_2] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action :check_environment_before_2, EnvironmentBoundary,
    ctx: %{run_id: run_id},
    downstream: [:prepare_2] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action :prepare_2, PrepareReplica,
    ctx: %{run_id: run_id},
    downstream: [:mark_plan_dispatch_2],
    store_result: true do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 2]
  end

  task_action :mark_plan_dispatch_2, TimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_plan_2] do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 2, event_kind: :plan_dispatch]
  end

  task_action :run_plan_2, RunPlan,
    map_over: :prepare_2,
    ctx: %{params: params},
    downstream: [:mark_plan_completion_2] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_plan_completion_2, TimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:mark_simulation_dispatch_2] do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 2, event_kind: :plan_completion]
  end

  task_action :mark_simulation_dispatch_2, TimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_simulation_2] do
    [
      study_phase_run_id: phase_run_id(run_id),
      replica_position: 2,
      event_kind: :simulation_dispatch
    ]
  end

  task_action :run_simulation_2, RunSimulation,
    map_over: :prepare_2,
    ctx: %{params: params},
    downstream: [:mark_simulation_completion_2] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_simulation_completion_2, TimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:check_environment_after_2] do
    [
      study_phase_run_id: phase_run_id(run_id),
      replica_position: 2,
      event_kind: :simulation_completion
    ]
  end

  task_action :check_environment_after_2, EnvironmentBoundary,
    ctx: %{run_id: run_id},
    downstream: [:check_environment_before_3] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action :check_environment_before_3, EnvironmentBoundary,
    ctx: %{run_id: run_id},
    downstream: [:prepare_3] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action :prepare_3, PrepareReplica,
    ctx: %{run_id: run_id},
    downstream: [:mark_plan_dispatch_3],
    store_result: true do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 3]
  end

  task_action :mark_plan_dispatch_3, TimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_plan_3] do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 3, event_kind: :plan_dispatch]
  end

  task_action :run_plan_3, RunPlan,
    map_over: :prepare_3,
    ctx: %{params: params},
    downstream: [:mark_plan_completion_3] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_plan_completion_3, TimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:mark_simulation_dispatch_3] do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 3, event_kind: :plan_completion]
  end

  task_action :mark_simulation_dispatch_3, TimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_simulation_3] do
    [
      study_phase_run_id: phase_run_id(run_id),
      replica_position: 3,
      event_kind: :simulation_dispatch
    ]
  end

  task_action :run_simulation_3, RunSimulation,
    map_over: :prepare_3,
    ctx: %{params: params},
    downstream: [:mark_simulation_completion_3] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_simulation_completion_3, TimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:check_environment_after_3] do
    [
      study_phase_run_id: phase_run_id(run_id),
      replica_position: 3,
      event_kind: :simulation_completion
    ]
  end

  task_action :check_environment_after_3, EnvironmentBoundary,
    ctx: %{run_id: run_id},
    downstream: [:check_environment_before_4] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action :check_environment_before_4, EnvironmentBoundary,
    ctx: %{run_id: run_id},
    downstream: [:prepare_4] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action :prepare_4, PrepareReplica,
    ctx: %{run_id: run_id},
    downstream: [:mark_plan_dispatch_4],
    store_result: true do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 4]
  end

  task_action :mark_plan_dispatch_4, TimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_plan_4] do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 4, event_kind: :plan_dispatch]
  end

  task_action :run_plan_4, RunPlan,
    map_over: :prepare_4,
    ctx: %{params: params},
    downstream: [:mark_plan_completion_4] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_plan_completion_4, TimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:mark_simulation_dispatch_4] do
    [study_phase_run_id: phase_run_id(run_id), replica_position: 4, event_kind: :plan_completion]
  end

  task_action :mark_simulation_dispatch_4, TimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_simulation_4] do
    [
      study_phase_run_id: phase_run_id(run_id),
      replica_position: 4,
      event_kind: :simulation_dispatch
    ]
  end

  task_action :run_simulation_4, RunSimulation,
    map_over: :prepare_4,
    ctx: %{params: params},
    downstream: [:mark_simulation_completion_4] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_simulation_completion_4, TimingBoundary,
    ctx: %{run_id: run_id},
    downstream: [:check_environment_after_4] do
    [
      study_phase_run_id: phase_run_id(run_id),
      replica_position: 4,
      event_kind: :simulation_completion
    ]
  end

  task_action :check_environment_after_4, EnvironmentBoundary,
    ctx: %{run_id: run_id},
    downstream: [:complete_final_tier] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action(:complete_final_tier, {CompleteTier, []}, store_result: true)
end
