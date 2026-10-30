defmodule NetworkDefense.Evaluation2.Study.Workflow.PilotCollection.Actions.Prepare do
  @moduledoc false

  # First Pilot collection task. It plans the ordered work of the run and
  # materializes the replica-0 item batch that both mapped tasks consume.

  @behaviour Gust.Action

  alias NetworkDefense.Evaluation2.Study.Collection
  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Persistence.CollectionItem
  alias NetworkDefense.Evaluation2.Study.Persistence.CollectionPlan
  alias NetworkDefense.Evaluation2.Study.Workflow.PilotCollection.Actions.Boundary

  @replica_position 0
  @failure "Evaluation2 Pilot collection preparation failed"

  @impl Gust.Action
  def execute(args, action_context) do
    with {:ok, context} <- Boundary.run_context(Keyword.fetch!(args, :params), action_context),
         {:ok, plan} <- plan(context),
         {:ok, items} <- replica_items(plan) do
      encode_items(items)
    else
      {:error, cause} -> fail(cause)
    end
  end

  @spec plan(Persistence.phase_run_context()) ::
          {:ok, CollectionPlan.t()} | {:error, term()}
  defp plan(context) do
    Boundary.logged(
      @failure,
      Collection.prepare_pilot(context.phase_run.id, context.revision.definition)
    )
  end

  @spec replica_items(CollectionPlan.t()) ::
          {:ok, [CollectionItem.t()]} | {:error, term()}
  defp replica_items(plan) do
    Boundary.logged(@failure, Collection.prepare_replica(plan.id, @replica_position))
  end

  @spec encode_items([CollectionItem.t()]) :: [%{required(String.t()) => Ecto.UUID.t()}]
  defp encode_items(items), do: Enum.map(items, &%{"collection_item_id" => &1.id})

  # A tagged collection failure is permanent, so Gust must not retry the task.
  @spec fail(term()) :: no_return()
  defp fail(_cause), do: raise(Gust.DAG.NonRecError, @failure)
end
