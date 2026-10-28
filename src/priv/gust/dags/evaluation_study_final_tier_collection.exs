defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.DAG do
  @moduledoc false
  use Gust.DSL, on_finished_callback: :notify_waiters
  use NetworkDefense.Evaluation.Study.Pipeline.GustCallback

  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.{
    CompleteTier,
    EnvironmentBoundary,
    PrepareReplica,
    RunPlan,
    RunSimulation
  }

  import NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.MeasuredReplica.DAG

  # Warm-up, five measured replicas, and one completion.
  #
  # The environment is checked before the warm-up, before the first measured
  # replica, between adjacent measured replicas, and after the last one. Each
  # check re-reads the deployed revision, so a change during the run stops it.
  #
  # Static tasks read run parameters. Only mapped tasks receive item parameters.
  defp phase_run_id(run_id), do: Gust.Flows.get_run!(run_id).params["study_phase_run_id"]

  task_action :check_environment_before_warm_up, EnvironmentBoundary.Gust,
    ctx: %{run_id: run_id},
    downstream: [:prepare_warm_up] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action :prepare_warm_up, PrepareReplica.Gust,
    ctx: %{run_id: run_id},
    downstream: [:run_plan_warm_up],
    store_result: true do
    [study_phase_run_id: phase_run_id(run_id), replica_position: -1]
  end

  task_action :run_plan_warm_up, RunPlan.Gust,
    map_over: :prepare_warm_up,
    ctx: %{params: params},
    downstream: [:run_simulation_warm_up] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :run_simulation_warm_up, RunSimulation.Gust,
    map_over: :prepare_warm_up,
    ctx: %{params: params},
    downstream: [:check_environment_before_0] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :check_environment_before_0, EnvironmentBoundary.Gust,
    ctx: %{run_id: run_id},
    downstream: [:prepare_0] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  measured_replica(0, after: :check_environment_after_0)

  task_action :check_environment_after_0, EnvironmentBoundary.Gust,
    ctx: %{run_id: run_id},
    downstream: [:prepare_1] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  measured_replica(1, after: :check_environment_after_1)

  task_action :check_environment_after_1, EnvironmentBoundary.Gust,
    ctx: %{run_id: run_id},
    downstream: [:prepare_2] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  measured_replica(2, after: :check_environment_after_2)

  task_action :check_environment_after_2, EnvironmentBoundary.Gust,
    ctx: %{run_id: run_id},
    downstream: [:prepare_3] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  measured_replica(3, after: :check_environment_after_3)

  task_action :check_environment_after_3, EnvironmentBoundary.Gust,
    ctx: %{run_id: run_id},
    downstream: [:prepare_4] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  measured_replica(4, after: :check_environment_after_4)

  task_action :check_environment_after_4, EnvironmentBoundary.Gust,
    ctx: %{run_id: run_id},
    downstream: [:complete_final_tier] do
    [study_phase_run_id: phase_run_id(run_id)]
  end

  task_action(:complete_final_tier, {CompleteTier.Gust, []}, store_result: true)
end
