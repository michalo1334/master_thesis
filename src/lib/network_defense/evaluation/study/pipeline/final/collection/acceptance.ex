defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.Acceptance do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.Handoff

  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.IO, as: AnalysisIO
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.IO
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.TierRuns
  alias NetworkDefense.Evaluation.Study.Pipeline.State
  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase}
  alias NetworkDefense.Repo

  # Acceptance of one complete Final collection.
  #
  # The transition runs under the execution lock, then the collection phase lock.
  # It accepts the snapshot only for a complete ordered tier family, persists the
  # Final analysis handoff in `result_ref`, keeps no scalar Gust run on the
  # collection phase, and creates the Final analysis phase once. A repeated
  # attempt accepts only the identical snapshot and handoff instead of
  # inserting a second phase or rewriting another handoff.
  #
  # A late attempt that finds another state stops without linking a snapshot,
  # persisting a handoff, creating a phase, or reviving the execution.
  @spec run(IO.t(), Ecto.UUID.t(), term()) ::
          {:ok, AnalysisIO.t()} | {:error, StudyError.t()} | {:stop, atom()}
  def run(%IO{} = io, snapshot_id, timing_summary) do
    execution_id = io.execution.id

    case State.transaction(execution_id, &locked_accept(&1, io, snapshot_id, timing_summary)) do
      {execution, phase, handoff} ->
        {:ok, analysis_io(io, execution, phase, handoff)}

      other ->
        other
    end
  end

  defp locked_accept(
         %StudyExecution{state: :collecting_final} = execution,
         %IO{} = io,
         snapshot_id,
         timing_summary
       ) do
    phase = State.lock_named_phase(execution.id, :final_collection)

    with {:ok, rows} <- ordered_family(phase, io.tiers),
         {:ok, handoff} <- Handoff.new(io.tiers, rows, timing_summary) do
      accept_snapshot(execution, phase, snapshot_id, handoff)
    else
      {:error, %StudyError{} = error} -> Repo.rollback({:error, error})
    end
  end

  defp locked_accept(%StudyExecution{state: state}, _io, _snapshot_id, _timing_summary),
    do: State.stop(state)

  # The snapshot and the handoff describe the same accepted collection, so both
  # are stored in one phase update. A repeated acceptance must repeat the
  # identical values.
  defp accept_snapshot(%StudyExecution{} = execution, phase, snapshot_id, %Handoff{} = handoff) do
    params = Handoff.to_params(handoff)

    with :ok <- identical_or_empty(phase.snapshot_id, snapshot_id),
         :ok <- identical_or_empty(phase.result_ref, params) do
      State.update_phase!(phase, %{snapshot_id: snapshot_id, result_ref: params})
      accept(execution, handoff)
    else
      {:error, %StudyError{} = error} -> Repo.rollback({:error, error})
    end
  end

  defp accept(%StudyExecution{} = execution, %Handoff{} = handoff) do
    transitioned = State.transition!(execution, :final_collected)
    {transitioned, analysis_phase!(execution.id), handoff}
  end

  defp identical_or_empty(nil, _expected), do: :ok
  defp identical_or_empty(existing, expected) when existing == expected, do: :ok

  defp identical_or_empty(_existing, _expected),
    do: {:error, StudyError.final_collection_workflow_failed()}

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

  # The in-process handoff and the reloaded one describe the same contract: the
  # same execution, phase, definition, snapshot, declared tiers, stored runs,
  # and timing summary.
  defp analysis_io(%IO{} = io, execution, phase, %Handoff{} = handoff) do
    %AnalysisIO{
      execution: execution,
      phase: phase,
      definition: io.definition,
      snapshot_id: phase.snapshot_id,
      tiers: handoff.tiers,
      runs: Enum.map(handoff.runs, &tier_run/1),
      timing: handoff.timing
    }
  end

  defp tier_run(%Handoff.Run{tier: tier, tier_position: position, gust_run_id: gust_run_id}) do
    %AnalysisIO.TierRun{
      tier: tier,
      tier_position: position,
      gust_run_id: gust_run_id
    }
  end
end
