defmodule NetworkDefense.Evaluation2.Study.Workflow.FinalTierCollection.Actions.MarkBoundary do
  @moduledoc false

  # Timing boundary task. It marks the start of the plan or the simulation stage
  # of one measured replica on the stored clock session. The warm-up replica
  # executes no measured mark.

  @behaviour Gust.Action

  alias NetworkDefense.Evaluation2.Study.Workflow.FinalTierCollection.Actions.Boundary

  @failure "Evaluation2 Final tier collection timing mark failed"

  @impl Gust.Action
  def execute(args, action_context) do
    with {:ok, {_context, prepared}} <-
           Boundary.prepared_run(Keyword.fetch!(args, :params), action_context),
         {:ok, nil} <-
           Boundary.mark_start(
             prepared.clock_session,
             Keyword.fetch!(args, :replica_position),
             Keyword.fetch!(args, :boundary)
           ) do
      :ok
    else
      {:error, cause} -> fail(cause)
    end
  end

  # A tagged timing failure is permanent, so Gust must not retry the task.
  @spec fail(term()) :: no_return()
  defp fail(_cause), do: raise(Gust.DAG.NonRecError, @failure)
end
