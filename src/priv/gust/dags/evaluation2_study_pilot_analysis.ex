defmodule NetworkDefense.Evaluation2.Study.Workflow.PilotAnalysis.DAG do
  @moduledoc """
  Gust DAG of the Pilot analysis phase.

  The run plans one job per declared candidate and comparison pair, assesses
  every job once, and selects the Pilot outcome from the complete batch. The
  mapped stage fans out over the prepared job batch in `map_index` order, so one
  stored assessment belongs to one job.

  The run input carries the phase-run UUID and the accepted snapshot UUID. The
  terminal task stores the encoded Pilot analysis output, because the outcome and
  the candidate summaries travel back through the completed Gust run. The tasks
  are thin adapters to the Pilot analysis capability and start no scientific
  work of their own.
  """

  use Gust.DSL

  alias NetworkDefense.Evaluation2.Study.Workflow.PilotAnalysis.Actions.{
    Evaluate,
    Prepare,
    SelectOutcome
  }

  # The static tasks read the run input; the prepare task decides whether it is
  # acceptable.
  defp run_params(run_id), do: Gust.Flows.get_run!(run_id).params

  task_action :prepare_pilot_analysis, Prepare,
    ctx: %{run_id: run_id},
    downstream: [:evaluate_pilot_candidate],
    store_result: true do
    [params: run_params(run_id)]
  end

  # Gust passes one prepared job as the mapped task parameters.
  task_action :evaluate_pilot_candidate, Evaluate,
    map_over: :prepare_pilot_analysis,
    ctx: %{run_id: run_id, params: job},
    downstream: [:select_pilot_outcome],
    store_result: true do
    [job: job, params: run_params(run_id)]
  end

  # The stored output is the completion payload of one Pilot analysis run.
  task_action :select_pilot_outcome, SelectOutcome,
    ctx: %{run_id: run_id},
    store_result: true do
    [params: run_params(run_id)]
  end
end
