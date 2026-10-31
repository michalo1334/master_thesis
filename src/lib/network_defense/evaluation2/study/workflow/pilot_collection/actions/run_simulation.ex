defmodule NetworkDefense.Evaluation2.Study.Workflow.PilotCollection.Actions.RunSimulation do
  @moduledoc false

  # Mapped Pilot collection task. It runs the simulation effect of the same
  # collection item that its optimization task already completed.

  @behaviour Gust.Action

  alias NetworkDefense.Evaluation2.Study.Collection
  alias NetworkDefense.Evaluation2.Study.Workflow.ActionBoundary
  alias NetworkDefense.Evaluation2.Study.Workflow.PilotCollection.Actions.Boundary

  @failure "Evaluation2 Pilot simulation failed"

  @impl Gust.Action
  def execute(args, %{run_id: run_id}) do
    ActionBoundary.run_effect(
      Keyword.fetch!(args, :collection_item_id),
      run_id,
      &Boundary.run_item/2,
      &Collection.run_simulation/1,
      @failure
    )
  end
end
