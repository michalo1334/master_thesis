defmodule NetworkDefense.Evaluation2.Study.Workflow.FinalTierCollection.Actions.CompleteReplica do
  @moduledoc false

  # Replica completion task. It closes the measured interval of one replica on
  # the stored clock session and stores the measured durations as the durable
  # timing receipt of that replica.

  @behaviour Gust.Action

  alias NetworkDefense.Evaluation2.Study.Result.Timing
  alias NetworkDefense.Evaluation2.Study.Workflow.FinalTierCollection.Actions.Boundary

  @failure "Evaluation2 Final tier collection replica completion failed"

  @impl Gust.Action
  def execute(args, action_context) do
    position = Keyword.fetch!(args, :replica_position)

    with {:ok, {_context, prepared}} <-
           Boundary.prepared_run(Keyword.fetch!(args, :params), action_context),
         {:ok, %Timing.Replica{} = replica} <-
           Boundary.mark_replica(prepared.clock_session, position) do
      Boundary.replica_params(position, replica)
    else
      {:error, cause} -> fail(cause)
    end
  end

  # A tagged timing failure is permanent, so Gust must not retry the task.
  @spec fail(term()) :: no_return()
  defp fail(_cause), do: raise(Gust.DAG.NonRecError, @failure)
end
