defmodule NetworkDefense.Evaluation2.Study.Workflow.FinalAnalysis.Actions.Prepare do
  @moduledoc false

  # First Final analysis task. It plans the comparison jobs of the accepted Final
  # snapshot and materializes the job batch that the mapped evaluation task
  # consumes.

  @behaviour Gust.Action

  alias NetworkDefense.Evaluation2.Study.Final.Analysis
  alias NetworkDefense.Evaluation2.Study.Final.ComparisonJob
  alias NetworkDefense.Evaluation2.Study.Workflow.FinalAnalysis.Actions.Boundary

  @failure "Evaluation2 Final analysis preparation failed"

  @impl Gust.Action
  def execute(args, action_context) do
    with {:ok, context} <- Boundary.run_context(Keyword.fetch!(args, :params), action_context),
         {:ok, jobs} <- prepare(context.input.snapshot_id),
         {:ok, params} <- Boundary.job_params(jobs) do
      params
    else
      {:error, cause} -> fail(cause)
    end
  end

  @spec prepare(Ecto.UUID.t()) :: {:ok, [ComparisonJob.t()]} | {:error, term()}
  defp prepare(snapshot_id) do
    Boundary.logged(@failure, Analysis.prepare(snapshot_id))
  end

  # A tagged analysis failure is permanent, so Gust must not retry the task.
  @spec fail(term()) :: no_return()
  defp fail(_cause), do: raise(Gust.DAG.NonRecError, @failure)
end
