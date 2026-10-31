defmodule NetworkDefense.Evaluation2.Study.Workflow.PilotAnalysis.Actions.Prepare do
  @moduledoc false

  # First Pilot analysis task. It plans the candidate and comparison jobs of the
  # accepted snapshot and materializes the job batch that the mapped evaluation
  # task consumes.

  @behaviour Gust.Action

  alias NetworkDefense.Evaluation2.Study.Pilot.Analysis
  alias NetworkDefense.Evaluation2.Study.Pilot.Job
  alias NetworkDefense.Evaluation2.Study.Workflow.PilotAnalysis.Actions.Boundary

  @failure "Evaluation2 Pilot analysis preparation failed"

  @impl Gust.Action
  def execute(args, action_context) do
    with {:ok, context} <- Boundary.run_context(Keyword.fetch!(args, :params), action_context),
         {:ok, jobs} <- prepare(context.input.snapshot_id) do
      Enum.map(jobs, &Boundary.job_to_params/1)
    else
      {:error, cause} -> fail(cause)
    end
  end

  @spec prepare(Ecto.UUID.t()) :: {:ok, [Job.t()]} | {:error, term()}
  defp prepare(snapshot_id) do
    Boundary.logged(@failure, Analysis.prepare(snapshot_id))
  end

  # A tagged analysis failure is permanent, so Gust must not retry the task.
  @spec fail(term()) :: no_return()
  defp fail(_cause), do: raise(Gust.DAG.NonRecError, @failure)
end
