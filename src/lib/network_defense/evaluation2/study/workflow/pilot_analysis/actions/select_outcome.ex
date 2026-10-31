defmodule NetworkDefense.Evaluation2.Study.Workflow.PilotAnalysis.Actions.SelectOutcome do
  @moduledoc false

  # Fan-in Pilot analysis task. It aggregates the stored assessment of every
  # mapped evaluation task and selects the Pilot outcome of the accepted
  # snapshot. The terminal task stores the encoded Pilot analysis output.

  @behaviour Gust.Action

  alias Gust.Flows
  alias NetworkDefense.Evaluation2.Study.Pilot.Analysis
  alias NetworkDefense.Evaluation2.Study.Pilot.AnalysisContract
  alias NetworkDefense.Evaluation2.Study.Pilot.Assessment
  alias NetworkDefense.Evaluation2.Study.Workflow.PilotAnalysis.Actions.Boundary

  @evaluation_task "evaluate_pilot_candidate"
  @failure "Evaluation2 Pilot outcome selection failed"

  @impl Gust.Action
  def execute(args, action_context) do
    with {:ok, context} <- Boundary.run_context(Keyword.fetch!(args, :params), action_context),
         {:ok, assessments} <- assessments(action_context.run_id),
         {:ok, output} <- decide(context.input.snapshot_id, assessments),
         {:ok, params} <- AnalysisContract.encode_output(output) do
      params
    else
      {:error, cause} -> fail(cause)
    end
  end

  # Gust starts fan-in after every mapped task succeeded, so the stored results
  # are complete and ordered by map index. Selection and its completeness checks
  # belong to the analysis capability.
  @spec assessments(pos_integer()) :: {:ok, [Assessment.t()]} | {:error, term()}
  defp assessments(run_id) do
    Boundary.logged(@failure, stored_assessments(run_id))
  end

  defp stored_assessments(run_id) do
    results =
      @evaluation_task
      |> Flows.get_tasks_by_name(run_id)
      |> Enum.map(& &1.result)

    Boundary.assessments(results)
  end

  @spec decide(Ecto.UUID.t(), [Assessment.t()]) ::
          {:ok, AnalysisContract.Output.t()} | {:error, term()}
  defp decide(snapshot_id, assessments) do
    Boundary.logged(@failure, Analysis.decide(snapshot_id, assessments))
  end

  # A tagged analysis failure is permanent, so Gust must not retry the task.
  @spec fail(term()) :: no_return()
  defp fail(_cause), do: raise(Gust.DAG.NonRecError, @failure)
end
