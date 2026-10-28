defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.Acceptance do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.IO, as: AnalysisIO
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.IO
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.TierRuns
  alias NetworkDefense.Evaluation.Study.Pipeline.State
  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase, StudyPhaseRun}
  alias NetworkDefense.Repo

  # Acceptance of one complete Final collection.
  #
  # The transition runs under the execution lock, then the collection phase lock.
  # It accepts the snapshot only for a complete ordered tier family, keeps no
  # scalar Gust run on the collection phase, and creates the Final analysis phase
  # once. A repeated attempt reuses that phase instead of inserting a second one.
  #
  # A late attempt that finds another state stops without linking a snapshot,
  # creating a phase, or reviving the execution.
  @spec run(IO.t(), Ecto.UUID.t(), term()) ::
          {:ok, AnalysisIO.t()} | {:error, StudyError.t()} | {:stop, atom()}
  def run(%IO{} = io, snapshot_id, timing_summary) do
    execution_id = io.execution.id

    case State.transaction(execution_id, &locked_accept(&1, io.tiers, snapshot_id)) do
      {execution, phase, rows} ->
        {:ok, analysis_io(io, execution, phase, rows, snapshot_id, timing_summary)}

      other ->
        other
    end
  end

  defp locked_accept(%StudyExecution{state: :collecting_final} = execution, tiers, snapshot_id) do
    phase = State.lock_named_phase(execution.id, :final_collection)

    case ordered_family(phase, tiers) do
      {:ok, rows} -> accept_snapshot(execution, phase, rows, snapshot_id)
      {:error, %StudyError{} = error} -> Repo.rollback({:error, error})
    end
  end

  defp locked_accept(%StudyExecution{state: state}, _tiers, _snapshot_id), do: State.stop(state)

  defp accept_snapshot(%StudyExecution{} = execution, phase, rows, snapshot_id) do
    case phase.snapshot_id do
      nil ->
        State.update_phase!(phase, %{snapshot_id: snapshot_id})
        accept(execution, rows)

      existing when existing == snapshot_id ->
        accept(execution, rows)

      _other_snapshot ->
        Repo.rollback({:error, StudyError.final_collection_workflow_failed()})
    end
  end

  defp accept(%StudyExecution{} = execution, rows) do
    transitioned = State.transition!(execution, :final_collected)
    {transitioned, analysis_phase!(execution.id), rows}
  end

  # Final analysis starts only for a complete ordered tier-run family. Final
  # collection keeps no scalar Gust run.
  defp ordered_family(%StudyPhase{id: phase_id, gust_run_id: scalar} = _phase, tiers) do
    with {:ok, rows} <- TierRuns.ordered_for_phase(phase_id),
         true <- is_nil(scalar),
         true <- Enum.map(rows, & &1.tier) == tiers,
         true <- Enum.all?(rows, &(is_integer(&1.gust_run_id) and &1.gust_run_id > 0)) do
      {:ok, rows}
    else
      false -> {:error, StudyError.incomplete_final_family()}
      {:error, %StudyError{} = error} -> {:error, error}
    end
  end

  defp analysis_phase!(execution_id) do
    case Repo.get_by(StudyPhase, execution_id: execution_id, phase: :final_analysis) do
      %StudyPhase{} = phase ->
        phase

      nil ->
        %StudyPhase{}
        |> StudyPhase.changeset(%{execution_id: execution_id, phase: :final_analysis})
        |> Repo.insert!()
    end
  end

  defp analysis_io(%IO{} = io, execution, phase, rows, snapshot_id, timing_summary) do
    %AnalysisIO{
      execution: execution,
      phase: phase,
      definition: io.definition,
      snapshot_id: snapshot_id,
      tiers: io.tiers,
      runs: Enum.map(rows, &tier_run/1),
      timing: timing_summary
    }
  end

  defp tier_run(%StudyPhaseRun{} = row) do
    %AnalysisIO.TierRun{
      tier: row.tier,
      tier_position: row.tier_position,
      gust_run_id: row.gust_run_id
    }
  end
end
