defmodule NetworkDefense.Evaluation2.Study.Workflow.FinalTierCollection.DAG do
  @moduledoc """
  Gust DAG of one Final tier collection run.

  The run prepares the tier plan and its timed clock session once, executes the
  excluded warm-up replica, and then executes the five measured replicas one
  after another. One replica prepares its own item batch, marks the start of its
  plan stage, runs the optimization effect of every item, marks the start of its
  simulation stage, runs the simulation effect of every item, and closes its
  measured interval with a stored timing receipt. The mapped stages fan out over
  the same item batch in `map_index` order, so each effect belongs to one plan
  entry.

  Every replica preparation and the terminal task re-read the measured
  environment label. The warm-up replica performs the same scientific work and
  records no measured mark. The terminal task gathers the five measured receipts
  and stores the encoded tier output, so a completed Gust run carries the tier
  receipt.

  The run input carries the canonical phase-run UUID of the tier, so the tier and
  the planned work come from the stored records of that run. The replica tasks
  are declared for every measured position, because the clock session requires
  the declared order of its markers.
  """

  use Gust.DSL

  alias NetworkDefense.Evaluation2.Study.Workflow.FinalTierCollection.Actions.{
    CompleteReplica,
    CompleteTier,
    MarkBoundary,
    PrepareReplica,
    PrepareTier,
    RunOptimization,
    RunSimulation
  }

  # The static tasks read the run input; the preparation task decides whether it
  # is acceptable.
  defp run_params(run_id), do: Gust.Flows.get_run!(run_id).params

  task_action :prepare_tier_collection, PrepareTier,
    ctx: %{run_id: run_id},
    downstream: [:prepare_warm_up_replica],
    store_result: true do
    [params: run_params(run_id)]
  end

  # The warm-up replica executes the same scientific work without measured marks.
  task_action :prepare_warm_up_replica, PrepareReplica,
    ctx: %{run_id: run_id},
    downstream: [:run_warm_up_optimization],
    store_result: true do
    [params: run_params(run_id), replica_position: -1]
  end

  task_action :run_warm_up_optimization, RunOptimization,
    map_over: :prepare_warm_up_replica,
    ctx: %{params: params},
    downstream: [:run_warm_up_simulation] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :run_warm_up_simulation, RunSimulation,
    map_over: :prepare_warm_up_replica,
    ctx: %{params: params},
    downstream: [:prepare_replica_0] do
    [collection_item_id: params["collection_item_id"]]
  end

  # Measured replica 0.
  task_action :prepare_replica_0, PrepareReplica,
    ctx: %{run_id: run_id},
    downstream: [:mark_plan_start_0],
    store_result: true do
    [params: run_params(run_id), replica_position: 0]
  end

  task_action :mark_plan_start_0, MarkBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_optimization_0] do
    [params: run_params(run_id), replica_position: 0, boundary: :plan_start]
  end

  task_action :run_optimization_0, RunOptimization,
    map_over: :prepare_replica_0,
    ctx: %{params: params},
    downstream: [:mark_simulation_start_0] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_simulation_start_0, MarkBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_simulation_0] do
    [params: run_params(run_id), replica_position: 0, boundary: :simulation_start]
  end

  task_action :run_simulation_0, RunSimulation,
    map_over: :prepare_replica_0,
    ctx: %{params: params},
    downstream: [:complete_replica_0] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :complete_replica_0, CompleteReplica,
    ctx: %{run_id: run_id},
    downstream: [:prepare_replica_1],
    store_result: true do
    [params: run_params(run_id), replica_position: 0]
  end

  # Measured replica 1.
  task_action :prepare_replica_1, PrepareReplica,
    ctx: %{run_id: run_id},
    downstream: [:mark_plan_start_1],
    store_result: true do
    [params: run_params(run_id), replica_position: 1]
  end

  task_action :mark_plan_start_1, MarkBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_optimization_1] do
    [params: run_params(run_id), replica_position: 1, boundary: :plan_start]
  end

  task_action :run_optimization_1, RunOptimization,
    map_over: :prepare_replica_1,
    ctx: %{params: params},
    downstream: [:mark_simulation_start_1] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_simulation_start_1, MarkBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_simulation_1] do
    [params: run_params(run_id), replica_position: 1, boundary: :simulation_start]
  end

  task_action :run_simulation_1, RunSimulation,
    map_over: :prepare_replica_1,
    ctx: %{params: params},
    downstream: [:complete_replica_1] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :complete_replica_1, CompleteReplica,
    ctx: %{run_id: run_id},
    downstream: [:prepare_replica_2],
    store_result: true do
    [params: run_params(run_id), replica_position: 1]
  end

  # Measured replica 2.
  task_action :prepare_replica_2, PrepareReplica,
    ctx: %{run_id: run_id},
    downstream: [:mark_plan_start_2],
    store_result: true do
    [params: run_params(run_id), replica_position: 2]
  end

  task_action :mark_plan_start_2, MarkBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_optimization_2] do
    [params: run_params(run_id), replica_position: 2, boundary: :plan_start]
  end

  task_action :run_optimization_2, RunOptimization,
    map_over: :prepare_replica_2,
    ctx: %{params: params},
    downstream: [:mark_simulation_start_2] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_simulation_start_2, MarkBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_simulation_2] do
    [params: run_params(run_id), replica_position: 2, boundary: :simulation_start]
  end

  task_action :run_simulation_2, RunSimulation,
    map_over: :prepare_replica_2,
    ctx: %{params: params},
    downstream: [:complete_replica_2] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :complete_replica_2, CompleteReplica,
    ctx: %{run_id: run_id},
    downstream: [:prepare_replica_3],
    store_result: true do
    [params: run_params(run_id), replica_position: 2]
  end

  # Measured replica 3.
  task_action :prepare_replica_3, PrepareReplica,
    ctx: %{run_id: run_id},
    downstream: [:mark_plan_start_3],
    store_result: true do
    [params: run_params(run_id), replica_position: 3]
  end

  task_action :mark_plan_start_3, MarkBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_optimization_3] do
    [params: run_params(run_id), replica_position: 3, boundary: :plan_start]
  end

  task_action :run_optimization_3, RunOptimization,
    map_over: :prepare_replica_3,
    ctx: %{params: params},
    downstream: [:mark_simulation_start_3] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_simulation_start_3, MarkBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_simulation_3] do
    [params: run_params(run_id), replica_position: 3, boundary: :simulation_start]
  end

  task_action :run_simulation_3, RunSimulation,
    map_over: :prepare_replica_3,
    ctx: %{params: params},
    downstream: [:complete_replica_3] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :complete_replica_3, CompleteReplica,
    ctx: %{run_id: run_id},
    downstream: [:prepare_replica_4],
    store_result: true do
    [params: run_params(run_id), replica_position: 3]
  end

  # Measured replica 4.
  task_action :prepare_replica_4, PrepareReplica,
    ctx: %{run_id: run_id},
    downstream: [:mark_plan_start_4],
    store_result: true do
    [params: run_params(run_id), replica_position: 4]
  end

  task_action :mark_plan_start_4, MarkBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_optimization_4] do
    [params: run_params(run_id), replica_position: 4, boundary: :plan_start]
  end

  task_action :run_optimization_4, RunOptimization,
    map_over: :prepare_replica_4,
    ctx: %{params: params},
    downstream: [:mark_simulation_start_4] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :mark_simulation_start_4, MarkBoundary,
    ctx: %{run_id: run_id},
    downstream: [:run_simulation_4] do
    [params: run_params(run_id), replica_position: 4, boundary: :simulation_start]
  end

  task_action :run_simulation_4, RunSimulation,
    map_over: :prepare_replica_4,
    ctx: %{params: params},
    downstream: [:complete_replica_4] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :complete_replica_4, CompleteReplica,
    ctx: %{run_id: run_id},
    downstream: [:complete_final_tier_collection],
    store_result: true do
    [params: run_params(run_id), replica_position: 4]
  end

  # The stored encoded output is the completion receipt and the tier timing
  # payload of one Final tier collection run.
  task_action :complete_final_tier_collection, CompleteTier,
    ctx: %{run_id: run_id},
    store_result: true do
    [params: run_params(run_id)]
  end
end
