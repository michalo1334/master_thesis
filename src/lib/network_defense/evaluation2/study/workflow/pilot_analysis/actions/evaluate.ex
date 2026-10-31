defmodule NetworkDefense.Evaluation2.Study.Workflow.PilotAnalysis.Actions.Evaluate do
  @moduledoc false

  # Mapped Pilot analysis task. It assesses one prepared candidate and comparison
  # job against the accepted snapshot of the acting Gust run, and stores the
  # assessment for the fan-in task.

  @behaviour Gust.Action

  alias NetworkDefense.Evaluation2.Study.Pilot.Analysis
  alias NetworkDefense.Evaluation2.Study.Pilot.Assessment
  alias NetworkDefense.Evaluation2.Study.Pilot.Job
  alias NetworkDefense.Evaluation2.Study.Workflow.PilotAnalysis.Actions.Boundary

  @failure "Evaluation2 Pilot assessment failed"

  @impl Gust.Action
  def execute(args, action_context) do
    with {:ok, context} <- Boundary.run_context(Keyword.fetch!(args, :params), action_context),
         {:ok, job} <- Boundary.run_job(Keyword.fetch!(args, :job)),
         {:ok, assessment} <- evaluate(context.input.snapshot_id, job) do
      Boundary.assessment_to_params(assessment)
    else
      {:error, cause} -> fail(cause)
    end
  end

  @spec evaluate(Ecto.UUID.t(), Job.t()) :: {:ok, Assessment.t()} | {:error, term()}
  defp evaluate(snapshot_id, job) do
    Boundary.logged(@failure, Analysis.evaluate(snapshot_id, job))
  end

  # A tagged analysis failure is permanent, so Gust must not retry the task.
  @spec fail(term()) :: no_return()
  defp fail(_cause), do: raise(Gust.DAG.NonRecError, @failure)
end
