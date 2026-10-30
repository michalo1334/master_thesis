defmodule NetworkDefense.Evaluation2.Study.Workflow.PilotCollection.DAG do
  @moduledoc """
  Gust DAG of the Pilot Collection phase.

  The run plans the ordered Pilot work once, runs the optimization and then the
  simulation effect of every item, and assembles the phase-owned evidence
  snapshot from the complete batch. Both mapped stages fan out over the same item
  batch in `map_index` order, so each effect belongs to one plan entry.

  The run input carries the phase-run UUID, and the terminal task stores the
  empty Pilot Collection output, because the collection phase owns its snapshot.
  The tasks are thin adapters to the collection capability and start no
  scientific work of their own.
  """

  use Gust.DSL

  alias NetworkDefense.Evaluation2.Study.Workflow.PilotCollection.Actions.{
    Assemble,
    Prepare,
    RunOptimization,
    RunSimulation
  }

  # Both static tasks read the run input; the prepare task decides whether it is
  # acceptable.
  defp run_params(run_id), do: Gust.Flows.get_run!(run_id).params

  task_action :prepare_pilot_collection, Prepare,
    ctx: %{run_id: run_id},
    downstream: [:run_pilot_optimization],
    store_result: true do
    [params: run_params(run_id)]
  end

  task_action :run_pilot_optimization, RunOptimization,
    map_over: :prepare_pilot_collection,
    ctx: %{params: params},
    downstream: [:run_pilot_simulation] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :run_pilot_simulation, RunSimulation,
    map_over: :prepare_pilot_collection,
    ctx: %{params: params},
    downstream: [:assemble_pilot_snapshot] do
    [collection_item_id: params["collection_item_id"]]
  end

  task_action :assemble_pilot_snapshot, Assemble,
    ctx: %{run_id: run_id},
    downstream: [:complete_pilot_collection] do
    [params: run_params(run_id)]
  end

  # The stored empty object is the completion receipt of one Pilot Collection run.
  task :complete_pilot_collection, ctx: %{}, store_result: true do
    %{}
  end
end
