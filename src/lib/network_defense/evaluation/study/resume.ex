defmodule NetworkDefense.Evaluation.Study.Resume do
  @moduledoc false

  import Ecto.Query

  alias NetworkDefense.Evaluation.Study.Contracts.{Definition, StudyError}

  alias NetworkDefense.Evaluation.Study.{
    Coordinator,
    FinalSelection,
    Lifecycle,
    PilotOutcome,
    Revisions
  }

  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase}
  alias NetworkDefense.Repo

  @type final_selection ::
          :recommended
          | {:override_insufficient, candidate_id :: String.t()}

  @spec resume(Ecto.UUID.t(), final_selection()) ::
          {:ok, StudyExecution.t()} | {:error, StudyError.t()}
  def resume(execution_id, selection), do: resume(execution_id, selection, [])

  @doc false
  @spec resume(Ecto.UUID.t(), final_selection(), keyword()) ::
          {:ok, StudyExecution.t()} | {:error, StudyError.t()}
  def resume(execution_id, selection, opts) do
    coordinator = Keyword.get(opts, :coordinator, Coordinator)

    with {:ok, id} <- cast_execution_id(execution_id),
         {:ok, execution} <- id |> resume_transaction(selection) |> transaction_result(),
         {:ok, _pid} <- coordinator.start(execution.id) do
      {:ok, execution}
    end
  rescue
    _exception in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:error, StudyError.final_selection_storage_failed()}
  end

  defp cast_execution_id(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, StudyError.study_execution_not_found()}
    end
  end

  defp resume_transaction(execution_id, selection) do
    Repo.transaction(fn ->
      execution = execution_id |> lock_execution() |> unwrap()
      :ok = execution |> require_awaiting_final() |> unwrap()
      outcome = execution.pilot_outcome |> parse_pilot_outcome() |> unwrap()
      definition = execution.study_revision_id |> Revisions.load_definition() |> unwrap()
      _pilot_phase = execution |> accepted_pilot_phase() |> unwrap()

      {candidate, pilot_override} =
        definition |> resolve_candidate(outcome, selection) |> unwrap()

      frozen_selection = candidate |> FinalSelection.from_candidate(pilot_override) |> unwrap()
      state = execution.state |> Lifecycle.transition(:resume) |> resume_state() |> unwrap()

      resumed =
        execution
        |> StudyExecution.changeset(
          frozen_selection
          |> FinalSelection.to_execution_attrs()
          |> Map.put(:state, state)
        )
        |> update_execution()
        |> unwrap()

      :ok = execution.id |> ensure_empty_final_phase() |> unwrap()
      resumed
    end)
  end

  defp transaction_result({:ok, %StudyExecution{} = execution}), do: {:ok, execution}
  defp transaction_result({:error, %StudyError{} = error}), do: {:error, error}
  defp transaction_result(_result), do: {:error, StudyError.final_selection_storage_failed()}

  defp lock_execution(execution_id) do
    case Repo.one(
           from execution in StudyExecution,
             where: execution.id == ^execution_id,
             lock: "FOR UPDATE"
         ) do
      %StudyExecution{} = execution -> {:ok, execution}
      nil -> {:error, StudyError.study_execution_not_found()}
    end
  end

  defp require_awaiting_final(%StudyExecution{state: :awaiting_final}), do: {:ok, :ok}
  defp require_awaiting_final(_execution), do: {:error, StudyError.final_resume_not_allowed()}

  defp parse_pilot_outcome(params) do
    case PilotOutcome.parse(params) do
      {:ok, %PilotOutcome{} = outcome} -> {:ok, outcome}
      {:error, %StudyError{}} -> {:error, StudyError.pilot_source_incomplete()}
    end
  end

  defp accepted_pilot_phase(%StudyExecution{} = execution) do
    phase =
      Repo.one(
        from phase in StudyPhase,
          where: phase.execution_id == ^execution.id and phase.phase == :pilot_analysis,
          lock: "FOR UPDATE"
      )

    if complete_pilot_phase?(phase, execution.pilot_outcome) do
      {:ok, phase}
    else
      {:error, StudyError.pilot_source_incomplete()}
    end
  end

  defp complete_pilot_phase?(%StudyPhase{} = phase, pilot_outcome) do
    is_integer(phase.gust_run_id) and phase.gust_run_id > 0 and
      phase.result_ref == pilot_outcome and is_nil(phase.error)
  end

  defp complete_pilot_phase?(_phase, _pilot_outcome), do: false

  defp resolve_candidate(
         %Definition{} = definition,
         %PilotOutcome{outcome: :recommended} = outcome,
         :recommended
       ) do
    case find_candidate(definition, outcome.candidate_id) do
      nil ->
        {:error, StudyError.selected_candidate_not_declared()}

      candidate ->
        if candidate_counts_match?(candidate, outcome) do
          {:ok, {candidate, false}}
        else
          {:error, StudyError.pilot_source_incomplete()}
        end
    end
  end

  defp resolve_candidate(
         %Definition{} = definition,
         %PilotOutcome{outcome: :insufficient},
         {:override_insufficient, candidate_id}
       )
       when is_binary(candidate_id) do
    case find_candidate(definition, candidate_id) do
      nil -> {:error, StudyError.selected_candidate_not_declared()}
      candidate -> {:ok, {candidate, true}}
    end
  end

  defp resolve_candidate(_definition, _outcome, _selection),
    do: {:error, StudyError.final_selection_invalid()}

  defp find_candidate(%Definition{pilot: pilot}, candidate_id) do
    Enum.find(pilot.candidates, &(&1.id == candidate_id))
  end

  defp candidate_counts_match?(candidate, %PilotOutcome{} = outcome) do
    candidate.plan_count_per_side == outcome.plan_count_per_side and
      candidate.attacks_per_plan == outcome.attacks_per_plan
  end

  defp resume_state({:ok, :collecting_final}), do: {:ok, :collecting_final}
  defp resume_state(_transition), do: {:error, StudyError.final_resume_not_allowed()}

  defp update_execution(changeset) do
    case Repo.update(changeset) do
      {:ok, %StudyExecution{} = execution} -> {:ok, execution}
      {:error, _changeset} -> {:error, StudyError.final_selection_storage_failed()}
    end
  end

  defp ensure_empty_final_phase(execution_id) do
    case lock_final_phase(execution_id) do
      nil -> insert_final_phase(execution_id)
      %StudyPhase{} = phase -> validate_empty_final_phase(phase)
    end
  end

  defp lock_final_phase(execution_id) do
    Repo.one(
      from phase in StudyPhase,
        where: phase.execution_id == ^execution_id and phase.phase == :final_collection,
        lock: "FOR UPDATE"
    )
  end

  defp insert_final_phase(execution_id) do
    %StudyPhase{}
    |> StudyPhase.changeset(%{execution_id: execution_id, phase: :final_collection})
    |> Repo.insert()
    |> case do
      {:ok, %StudyPhase{}} -> {:ok, :ok}
      {:error, _changeset} -> {:error, StudyError.final_selection_storage_failed()}
    end
  end

  defp validate_empty_final_phase(%StudyPhase{} = phase) do
    if Enum.all?(
         [phase.gust_run_id, phase.snapshot_id, phase.result_ref, phase.error],
         &is_nil/1
       ) do
      {:ok, :ok}
    else
      {:error, StudyError.final_phase_conflict()}
    end
  end

  defp unwrap({:ok, value}), do: value
  defp unwrap({:error, %StudyError{} = error}), do: Repo.rollback(error)
end
