defmodule NetworkDefense.Evaluation2.Study.Workflow.FinalAnalysis.DAG do
  @moduledoc """
  Gust DAG of the Final analysis phase.

  The run plans one job per declared comparison, evaluates every job once, and
  corrects the complete declared family. The mapped stage fans out over the
  prepared job batch in `map_index` order, so one stored evaluation belongs to
  one declared comparison.

  The run input carries the phase-run UUID and the accepted Final snapshot UUID.
  The terminal task stores the encoded corrected family, because the family
  travels back through the completed Gust run and the acceptance transaction
  reads it from there. The tasks are thin adapters to the Final analysis
  capability and start no scientific work of their own.
  """

  use Gust.DSL

  alias NetworkDefense.Evaluation2.Study.Workflow.FinalAnalysis.Actions.{
    Correct,
    Evaluate,
    Prepare
  }

  # The static tasks read the run input; the prepare task decides whether it is
  # acceptable.
  defp run_params(run_id), do: Gust.Flows.get_run!(run_id).params

  task_action :prepare_final_analysis, Prepare,
    ctx: %{run_id: run_id},
    downstream: [:evaluate_final_comparison],
    store_result: true do
    [params: run_params(run_id)]
  end

  # Gust passes one prepared job as the mapped task parameters.
  task_action :evaluate_final_comparison, Evaluate,
    map_over: :prepare_final_analysis,
    ctx: %{run_id: run_id, params: job},
    downstream: [:correct_final_family],
    store_result: true do
    [job: job, params: run_params(run_id)]
  end

  # The stored output is the completion payload of one Final analysis run.
  task_action :correct_final_family, Correct,
    ctx: %{run_id: run_id},
    store_result: true do
    [params: run_params(run_id)]
  end
end
