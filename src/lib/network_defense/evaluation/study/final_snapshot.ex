defmodule NetworkDefense.Evaluation.Study.FinalSnapshot do
  @moduledoc false

  import Ecto.Query

  alias NetworkDefense.Evaluation.EvidenceSnapshots
  alias NetworkDefense.Evaluation.Final.Contracts.SnapshotInput
  alias NetworkDefense.Evaluation.Study.Contracts.{Definition, StudyError}
  alias NetworkDefense.Evaluation.Study.PilotSnapshot

  alias NetworkDefense.Evaluation.{
    EvidenceSnapshot,
    StudyCollectionItem,
    StudyExecution,
    StudyPhase
  }

  alias NetworkDefense.Repo

  @collection_phase :final_collection

  @spec assemble_and_store(StudyPhase.t(), [StudyCollectionItem.t()], Definition.t()) ::
          {:ok, Ecto.UUID.t()} | {:error, StudyError.t()}
  def assemble_and_store(
        %StudyPhase{} = phase,
        collection_items,
        %Definition{} = definition
      )
      when is_list(collection_items) do
    transaction_result(
      Repo.transaction(fn ->
        with %StudyPhase{} = locked <- lock_phase(phase.id),
             :ok <- require_final_phase(locked) do
          link_or_create(locked, collection_items, definition)
        else
          nil -> Repo.rollback({:error, StudyError.invalid_study_phase()})
          {:error, %StudyError{} = error} -> Repo.rollback({:error, error})
        end
      end)
    )
  rescue
    _exception in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:error, StudyError.final_snapshot_storage_failed()}
  end

  def assemble_and_store(_phase, _collection_items, _definition),
    do: incomplete(["collection_items"])

  defp transaction_result({:ok, {:ok, snapshot_id}}), do: {:ok, snapshot_id}
  defp transaction_result({:error, {:error, %StudyError{} = error}}), do: {:error, error}
  defp transaction_result(_result), do: {:error, StudyError.final_snapshot_storage_failed()}

  defp lock_phase(phase_id) do
    case Ecto.UUID.cast(phase_id) do
      {:ok, id} -> Repo.one(from phase in StudyPhase, where: phase.id == ^id, lock: "FOR UPDATE")
      :error -> nil
    end
  end

  defp require_final_phase(%StudyPhase{phase: @collection_phase}), do: :ok

  defp require_final_phase(%StudyPhase{phase: phase}),
    do: {:error, StudyError.unsupported_collection_phase(phase)}

  defp link_or_create(%StudyPhase{snapshot_id: snapshot_id} = phase, _items, definition)
       when is_binary(snapshot_id) do
    with {:ok, %EvidenceSnapshot{} = snapshot, _payload} <- load_existing(snapshot_id),
         :ok <- validate_existing(snapshot, phase, definition) do
      {:ok, snapshot.id}
    else
      _invalid -> Repo.rollback(incomplete(["snapshot_id"]))
    end
  end

  defp link_or_create(%StudyPhase{} = phase, items, definition) do
    with {:ok, execution} <- load_execution(phase.execution_id),
         :ok <- reject_pilot_reuse(execution, items),
         {:ok, {comparisons, _runtime_evidence}} <- assemble_evidence(phase, items, definition),
         {:ok, input} <- snapshot_input(execution, definition, comparisons),
         {:ok, snapshot} <- create_snapshot(input),
         {:ok, linked} <- link_snapshot(phase, snapshot.id) do
      {:ok, linked.snapshot_id}
    else
      {:error, %StudyError{} = error} -> Repo.rollback({:error, error})
    end
  end

  defp load_existing(snapshot_id), do: EvidenceSnapshots.load_final(snapshot_id)

  defp validate_existing(%EvidenceSnapshot{} = snapshot, %StudyPhase{} = phase, definition) do
    with {:ok, execution} <- load_execution(phase.execution_id),
         true <- snapshot.study_revision_id == execution.study_revision_id,
         true <- snapshot.family_id == definition.family.id,
         true <- snapshot.schema_version == definition.schema_version do
      :ok
    else
      _invalid -> incomplete(["snapshot_id"])
    end
  end

  defp load_execution(execution_id) do
    case Repo.get(StudyExecution, execution_id) do
      %StudyExecution{} = execution -> {:ok, execution}
      nil -> {:error, StudyError.invalid_study_phase()}
    end
  end

  defp reject_pilot_reuse(%StudyExecution{} = execution, items) do
    pilot_items =
      Repo.all(
        from item in StudyCollectionItem,
          join: phase in StudyPhase,
          on: phase.id == item.study_phase_id,
          where: phase.execution_id == ^execution.id and phase.phase == :pilot_collection
      )

    supplied_ids = MapSet.new(items, & &1.id)
    supplied_optimizations = MapSet.new(items, & &1.optimization_run_id)
    supplied_experiments = MapSet.new(items, & &1.experiment_id)

    reused? =
      Enum.any?(pilot_items, fn item ->
        MapSet.member?(supplied_ids, item.id) or
          MapSet.member?(supplied_optimizations, item.optimization_run_id) or
          MapSet.member?(supplied_experiments, item.experiment_id)
      end)

    if reused?, do: incomplete(["collection_items"]), else: :ok
  end

  defp assemble_evidence(phase, items, definition) do
    case PilotSnapshot.assemble_evidence(phase, items, definition) do
      {:ok, result} -> {:ok, result}
      {:error, %StudyError{issues: [%{"path" => path} | _rest]}} -> incomplete(path)
      {:error, %StudyError{}} -> incomplete(["collection_items"])
    end
  end

  defp snapshot_input(execution, definition, comparisons) do
    attrs = %{
      "study_revision_id" => execution.study_revision_id,
      "phase" => "final",
      "schema_version" => definition.schema_version,
      "family_id" => definition.family.id,
      "payload" => %{
        "schema_version" => definition.schema_version,
        "evidence_role" => "final",
        "comparisons" => Enum.map(comparisons, &NetworkDefense.Contracts.to_params/1)
      }
    }

    case SnapshotInput.parse(attrs) do
      {:ok, input} -> {:ok, input}
      {:error, _error} -> incomplete(["payload"])
    end
  end

  defp create_snapshot(%SnapshotInput{} = input) do
    case EvidenceSnapshots.create_final(input) do
      {:ok, snapshot} -> {:ok, snapshot}
      {:error, _error} -> {:error, StudyError.final_snapshot_storage_failed()}
    end
  end

  defp link_snapshot(%StudyPhase{} = phase, snapshot_id) do
    case phase |> StudyPhase.changeset(%{snapshot_id: snapshot_id}) |> Repo.update() do
      {:ok, linked} -> {:ok, linked}
      {:error, _changeset} -> {:error, StudyError.final_snapshot_storage_failed()}
    end
  end

  defp incomplete(path), do: {:error, StudyError.incomplete_final_evidence(path)}
end
