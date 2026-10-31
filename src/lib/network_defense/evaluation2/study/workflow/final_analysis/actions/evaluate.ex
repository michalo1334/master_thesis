defmodule NetworkDefense.Evaluation2.Study.Workflow.FinalAnalysis.Actions.Evaluate do
  @moduledoc false

  # Mapped Final analysis task. It evaluates one prepared comparison job against
  # the accepted snapshot of the acting Gust run, and stores the statistics for
  # the fan-in task.

  @behaviour Gust.Action

  alias NetworkDefense.Evaluation2.Study.Final.Analysis
  alias NetworkDefense.Evaluation2.Study.Final.ComparisonJob
  alias NetworkDefense.Evaluation2.Study.Result.Comparison.Statistics
  alias NetworkDefense.Evaluation2.Study.Workflow.FinalAnalysis.Actions.Boundary

  @failure "Evaluation2 Final analysis evaluation failed"

  @impl Gust.Action
  def execute(args, action_context) do
    with {:ok, context} <- Boundary.run_context(Keyword.fetch!(args, :params), action_context),
         {:ok, job} <- Boundary.run_job(Keyword.fetch!(args, :job)),
         {:ok, statistics} <- evaluate(context.input.snapshot_id, job),
         {:ok, params} <- Boundary.evaluation_params(job, statistics) do
      params
    else
      # The stored statistics shape is the contract of the terminal family, so a
      # bare rejection of one evaluation is permanent too.
      :error -> fail(:invalid_evaluation)
      {:error, cause} -> fail(cause)
    end
  end

  @spec evaluate(Ecto.UUID.t(), ComparisonJob.t()) ::
          {:ok, Statistics.t()} | {:error, term()}
  defp evaluate(snapshot_id, job) do
    Boundary.logged(@failure, Analysis.evaluate(snapshot_id, job))
  end

  # A tagged analysis failure is permanent, so Gust must not retry the task.
  @spec fail(term()) :: no_return()
  defp fail(_cause), do: raise(Gust.DAG.NonRecError, @failure)
end
