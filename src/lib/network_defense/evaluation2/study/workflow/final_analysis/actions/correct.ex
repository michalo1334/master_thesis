defmodule NetworkDefense.Evaluation2.Study.Workflow.FinalAnalysis.Actions.Correct do
  @moduledoc false

  # Fan-in terminal Final analysis task. It gathers the stored evaluation of every
  # mapped comparison task, corrects the declared family, and stores the encoded
  # Final analysis output. The stored result is the completion payload that the
  # acceptance transaction decodes.

  @behaviour Gust.Action

  alias NetworkDefense.Evaluation2.Study.Final.Analysis
  alias NetworkDefense.Evaluation2.Study.Final.AnalysisContract
  alias NetworkDefense.Evaluation2.Study.Result.Comparison.Statistics
  alias NetworkDefense.Evaluation2.Study.Workflow.FinalAnalysis.Actions.Boundary

  @failure "Evaluation2 Final family correction failed"

  @impl Gust.Action
  def execute(args, action_context) do
    with {:ok, context} <- Boundary.run_context(Keyword.fetch!(args, :params), action_context),
         {:ok, statistics} <- statistics(action_context.run_id),
         {:ok, output} <- correct(context.input.snapshot_id, statistics),
         {:ok, params} <- encode(output) do
      params
    else
      {:error, cause} -> fail(cause)
    end
  end

  @spec statistics(pos_integer()) :: {:ok, [Statistics.t()]} | {:error, term()}
  defp statistics(run_id) do
    Boundary.logged(@failure, Boundary.stored_statistics(run_id))
  end

  @spec correct(Ecto.UUID.t(), [Statistics.t()]) ::
          {:ok, AnalysisContract.Output.t()} | {:error, term()}
  defp correct(snapshot_id, statistics) do
    Boundary.logged(@failure, Analysis.correct(snapshot_id, statistics))
  end

  @spec encode(AnalysisContract.Output.t()) :: {:ok, map()} | {:error, term()}
  defp encode(output) do
    case AnalysisContract.encode_output(output) do
      {:ok, params} -> {:ok, params}
      :error -> Boundary.tagged(:invalid_output, @failure)
    end
  end

  # A tagged analysis failure is permanent, so Gust must not retry the task.
  @spec fail(term()) :: no_return()
  defp fail(_cause), do: raise(Gust.DAG.NonRecError, @failure)
end
