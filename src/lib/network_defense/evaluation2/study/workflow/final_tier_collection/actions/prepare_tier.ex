defmodule NetworkDefense.Evaluation2.Study.Workflow.FinalTierCollection.Actions.PrepareTier do
  @moduledoc false

  # First Final tier collection task. It plans the immutable work of the tier and
  # opens the timed clock session of the run. The stored result carries the plan,
  # the session, the phase run, and the tier for every later task.

  @behaviour Gust.Action

  alias NetworkDefense.Evaluation2.Study.Collection
  alias NetworkDefense.Evaluation2.Study.Final.Timing
  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Persistence.CollectionPlan
  alias NetworkDefense.Evaluation2.Study.Selection
  alias NetworkDefense.Evaluation2.Study.Tier
  alias NetworkDefense.Evaluation2.Study.Workflow.FinalTierCollection.Actions.Boundary
  alias NetworkDefense.Evaluation2.Study.Workflow.FinalTierCollection.Actions.Prepared

  @failure "Evaluation2 Final tier collection preparation failed"

  @impl Gust.Action
  def execute(args, action_context) do
    with {:ok, context} <- Boundary.run_context(Keyword.fetch!(args, :params), action_context),
         {:ok, tier} <- Boundary.expect_tier(context.phase_run),
         {:ok, selection} <- Boundary.expect_selection(context.execution),
         {:ok, plan} <- plan(context, selection, tier),
         {:ok, clock_session} <- begin_tier(context.phase_run.id) do
      Boundary.prepared_params(%Prepared{
        plan_id: plan.id,
        clock_session: clock_session,
        phase_run_id: context.phase_run.id,
        tier: tier
      })
    else
      {:error, cause} -> fail(cause)
    end
  end

  @spec plan(Persistence.phase_run_context(), Selection.t(), Tier.t()) ::
          {:ok, CollectionPlan.t()} | {:error, term()}
  defp plan(context, selection, tier) do
    Boundary.logged(
      @failure,
      Collection.prepare_final(context.phase_run.id, context.revision.definition, selection, tier)
    )
  end

  @spec begin_tier(Ecto.UUID.t()) :: {:ok, binary()} | {:error, term()}
  defp begin_tier(phase_run_id) do
    Boundary.logged(@failure, Timing.begin_tier(phase_run_id))
  end

  # A tagged collection failure is permanent, so Gust must not retry the task.
  @spec fail(term()) :: no_return()
  defp fail(_cause), do: raise(Gust.DAG.NonRecError, @failure)
end
