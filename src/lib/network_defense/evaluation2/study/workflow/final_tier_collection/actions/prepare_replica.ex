defmodule NetworkDefense.Evaluation2.Study.Workflow.FinalTierCollection.Actions.PrepareReplica do
  @moduledoc false

  # Replica preparation task. It re-reads the measured environment label, creates
  # or loads the complete item batch of one replica, and hands the item
  # identities to the two mapped effect tasks. The warm-up replica uses position
  # -1 and measures nothing.

  @behaviour Gust.Action

  alias NetworkDefense.Evaluation2.Study.Collection
  alias NetworkDefense.Evaluation2.Study.Persistence.CollectionItem
  alias NetworkDefense.Evaluation2.Study.Workflow.FinalTierCollection.Actions.Boundary

  @failure "Evaluation2 Final tier collection replica preparation failed"

  @impl Gust.Action
  def execute(args, action_context) do
    with {:ok, {context, prepared}} <-
           Boundary.prepared_run(Keyword.fetch!(args, :params), action_context),
         :ok <-
           Boundary.logged_status(
             @failure,
             Boundary.expect_environment(context.revision.definition)
           ),
         {:ok, items} <- items(prepared.plan_id, Keyword.fetch!(args, :replica_position)) do
      Boundary.item_params(items)
    else
      {:error, cause} -> fail(cause)
    end
  end

  @spec items(Ecto.UUID.t(), CollectionItem.replica_position()) ::
          {:ok, [CollectionItem.t()]} | {:error, term()}
  defp items(plan_id, replica_position) do
    Boundary.logged(@failure, Collection.prepare_replica(plan_id, replica_position))
  end

  # A tagged collection failure is permanent, so Gust must not retry the task.
  @spec fail(term()) :: no_return()
  defp fail(_cause), do: raise(Gust.DAG.NonRecError, @failure)
end
