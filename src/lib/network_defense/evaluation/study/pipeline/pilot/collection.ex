defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis.IO, as: AnalysisIO
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.{Acceptance, IO, Workflow}
  alias NetworkDefense.Evaluation.Study.Pipeline.State

  @active_state :collecting_pilot

  # Runs one complete Pilot collection stage. The stage keeps the persisted Gust
  # run authoritative and returns the next stage input on success.
  @spec run(IO.t(), keyword()) ::
          {:ok, AnalysisIO.t()} | {:error, StudyError.t()} | {:stop, atom()}
  def run(%IO{} = io, opts \\ []) do
    workflow = Keyword.get(opts, :workflow, Workflow)

    with {:ok, run_id} <- workflow.create(io.phase),
         :ok <- State.accept_run(io.execution.id, @active_state, io.phase, run_id),
         :ok <- State.dispatch_run(io.execution.id, @active_state, io.phase, run_id, workflow),
         {:ok, snapshot_id} <- workflow.await(run_id) do
      Acceptance.accept_snapshot(io, snapshot_id)
    end
  end
end
