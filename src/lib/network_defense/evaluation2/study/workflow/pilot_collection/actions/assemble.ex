defmodule NetworkDefense.Evaluation2.Study.Workflow.PilotCollection.Actions.Assemble do
  @moduledoc false

  # Fan-in Pilot collection task. It assembles the one phase-owned evidence
  # snapshot from the complete item batch. The phase owns the snapshot, so the
  # task stores no payload.

  @behaviour Gust.Action

  alias NetworkDefense.Evaluation2.Study.Collection
  alias NetworkDefense.Evaluation2.Study.Persistence.EvidenceSnapshot
  alias NetworkDefense.Evaluation2.Study.Workflow.PilotCollection.Actions.Boundary

  @failure "Evaluation2 Pilot snapshot assembly failed"

  @impl Gust.Action
  def execute(args, action_context) do
    with {:ok, context} <- Boundary.run_context(Keyword.fetch!(args, :params), action_context),
         {:ok, %EvidenceSnapshot{}} <- assemble(context.phase.id) do
      :ok
    else
      {:error, cause} -> fail(cause)
    end
  end

  @spec assemble(Ecto.UUID.t()) :: {:ok, EvidenceSnapshot.t()} | {:error, term()}
  defp assemble(phase_id) do
    Boundary.logged(@failure, Collection.assemble_evidence(phase_id))
  end

  # A tagged collection failure is permanent, so Gust must not retry the task.
  @spec fail(term()) :: no_return()
  defp fail(_cause), do: raise(Gust.DAG.NonRecError, @failure)
end
