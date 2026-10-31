defmodule NetworkDefense.Evaluation2.Study.Workflow.FinalTierCollection.Actions.RunOptimization do
  @moduledoc false

  # Mapped Final tier collection task. It runs the optimization effect of one
  # ordered collection item that belongs to the phase run of the acting Gust run.

  @behaviour Gust.Action

  alias NetworkDefense.Evaluation2.Study.Collection
  alias NetworkDefense.Evaluation2.Study.Workflow.ActionBoundary
  alias NetworkDefense.Evaluation2.Study.Workflow.FinalTierCollection.Actions.Boundary

  @failure "Evaluation2 Final tier collection optimization failed"

  @impl Gust.Action
  def execute(args, %{run_id: run_id}) do
    ActionBoundary.run_effect(
      Keyword.fetch!(args, :collection_item_id),
      run_id,
      &Boundary.run_item/2,
      &Collection.run_optimization/1,
      @failure
    )
  end
end
