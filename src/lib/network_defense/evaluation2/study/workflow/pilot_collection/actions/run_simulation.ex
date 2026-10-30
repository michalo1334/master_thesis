defmodule NetworkDefense.Evaluation2.Study.Workflow.PilotCollection.Actions.RunSimulation do
  @moduledoc false

  # Mapped Pilot collection task. It runs the simulation effect of the same
  # collection item that its optimization task already completed.

  @behaviour Gust.Action

  alias NetworkDefense.Evaluation2.Study.Collection
  alias NetworkDefense.Evaluation2.Study.Workflow.PilotCollection.Actions.Boundary

  @failure "Evaluation2 Pilot simulation failed"

  @impl Gust.Action
  def execute(args, %{run_id: run_id}) do
    item_id = Keyword.fetch!(args, :collection_item_id)

    with {:ok, item} <- Boundary.run_item(item_id, run_id),
         :ok <- Boundary.logged_status(@failure, Collection.run_simulation(item.id)) do
      :ok
    else
      {:error, cause} -> fail(cause)
    end
  end

  # A tagged collection failure is permanent, so Gust must not retry the task.
  @spec fail(term()) :: no_return()
  defp fail(_cause), do: raise(Gust.DAG.NonRecError, @failure)
end
