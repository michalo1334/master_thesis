defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.DAG do
  @moduledoc false

  use Gust.DSL, on_finished_callback: :notify_waiters
  use NetworkDefense.Evaluation.Study.Pipeline.GustCallback

  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.{
    CompleteTier,
    EnvironmentBoundary,
    MeasuredReplica,
    PrepareReplica,
    RunPlan,
    RunSimulation
  }

  alias MeasuredReplica.DAG, as: MeasuredReplicaDAG
  require MeasuredReplicaDAG

  task_action :environment_before_warm_up, EnvironmentBoundary.Gust,
    downstream: [:prepare_warm_up]

  task_action :prepare_warm_up, PrepareReplica.Gust,
    downstream: [:run_plan_warm_up],
    store_result: true do
    [replica_position: -1]
  end

  task_action :run_plan_warm_up, RunPlan.Gust,
    map_over: :prepare_warm_up,
    ctx: %{params: params},
    downstream: [:run_simulation_warm_up] do
    [item: params]
  end

  task_action :run_simulation_warm_up, RunSimulation.Gust,
    map_over: :prepare_warm_up,
    ctx: %{params: params},
    downstream: [:environment_before_0] do
    [item: params]
  end

  task_action :environment_before_0, EnvironmentBoundary.Gust, downstream: [:prepare_0]

  MeasuredReplicaDAG.tasks(0, next: :environment_between_0_1)

  task_action :environment_between_0_1, EnvironmentBoundary.Gust, downstream: [:prepare_1]

  MeasuredReplicaDAG.tasks(1, next: :environment_between_1_2)

  task_action :environment_between_1_2, EnvironmentBoundary.Gust, downstream: [:prepare_2]

  MeasuredReplicaDAG.tasks(2, next: :environment_between_2_3)

  task_action :environment_between_2_3, EnvironmentBoundary.Gust, downstream: [:prepare_3]

  MeasuredReplicaDAG.tasks(3, next: :environment_between_3_4)

  task_action :environment_between_3_4, EnvironmentBoundary.Gust, downstream: [:prepare_4]

  MeasuredReplicaDAG.tasks(4, next: :environment_after_4)

  task_action :environment_after_4, EnvironmentBoundary.Gust, downstream: [:complete_tier]

  task_action :complete_tier, CompleteTier.Gust, store_result: true
end
