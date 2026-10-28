defmodule NetworkDefense.Evaluation.Study.FinalSnapshot do
  @moduledoc false

  import Ecto.Query

  alias NetworkDefense.Evaluation.EvidenceSnapshots
  alias NetworkDefense.Evaluation.Final.Contracts.SnapshotInput
  alias NetworkDefense.Evaluation.Study.Contracts.{Definition, StudyError}
  alias NetworkDefense.Evaluation.Study.{ExecutionAccess, PilotSnapshot}

  alias NetworkDefense.Evaluation.{
    EvidenceSnapshot,
    StudyCollectionItem,
    StudyExecution,
    StudyPhase
  }

  alias NetworkDefense.Repo

  @collection_phase :final_collection
  @replica_position 0

  # Accepts the Final snapshot of the measured replica.
  #
  # Evidence assembly reads immutable stored rows only, so it runs before the
  # short acceptance transaction. Acceptance locks the owning execution row
  # before the collection phase row: that is the only lock order used here, and
  # the Cancel command locks the execution row first as well. A cancellation that
  # commits first therefore leaves no evidence row and no linked snapshot, while
  # an acceptance that commits first keeps its snapshot. `:on_prepared` runs
  # between assembly and acceptance; tests use it to place a cancellation in that
  # window without timing assumptions.

  @type result :: {:ok, Ecto.UUID.t()} | {:error, StudyError.t()} | {:stop, atom()}

  @spec assemble_and_store(StudyPhase.t(), [StudyCollectionItem.t()], Definition.t(), keyword()) ::
          result()
  def assemble_and_store(phase, collection_items, definition, opts \\ [])

  def assemble_and_store(
        %StudyPhase{} = phase,
        collection_items,
        %Definition{} = definition,
        opts
      )
      when is_list(collection_items) and is_list(opts) do
    with :ok <- require_final_phase(phase),
         :ok <- require_replica_zero(phase, collection_items),
         {:ok, prepared} <- prepare(phase, collection_items, definition, opts) do
      accept(phase, collection_items, prepared, definition)
    end
  rescue
    _exception in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:error, StudyError.final_snapshot_storage_failed()}
  end

  def assemble_and_store(_phase, _collection_items, _definition, _opts),
    do: incomplete(["collection_items"])

  defp require_final_phase(%StudyPhase{phase: @collection_phase}), do: :ok

  defp require_final_phase(%StudyPhase{phase: phase}),
    do: {:error, StudyError.unsupported_collection_phase(phase)}

  # The snapshot holds one measured replica only. Warm-up rows and measured
  # positions 1..4 stay stored for inspection and never enter it.
  defp require_replica_zero(%StudyPhase{id: phase_id, phase: @collection_phase}, items) do
    valid? =
      Enum.all?(items, fn
        %StudyCollectionItem{study_phase_id: item_phase_id, replica_position: @replica_position}
        when item_phase_id == phase_id ->
          true

        _other ->
          false
      end)

    if valid?, do: :ok, else: incomplete(["collection_items"])
  end

  # A linked snapshot is accepted again by identity, so a repeated call never
  # assembles evidence twice.
  defp prepare(%StudyPhase{snapshot_id: snapshot_id}, _items, _definition, _opts)
       when is_binary(snapshot_id),
       do: {:ok, :linked}

  defp prepare(%StudyPhase{} = phase, items, %Definition{} = definition, opts) do
    with :ok <- reject_pilot_reuse(phase.execution_id, items),
         {:ok, {comparisons, _runtime_evidence}} <- assemble_evidence(phase, items, definition),
         :ok <- run_prepared_hook(opts) do
      {:ok, {:new, comparisons}}
    end
  end

  defp run_prepared_hook(opts) do
    case Keyword.get(opts, :on_prepared) do
      nil ->
        :ok

      fun when is_function(fun, 0) ->
        _result = fun.()
        :ok
    end
  end

  defp accept(%StudyPhase{} = phase, items, prepared, %Definition{} = definition) do
    Repo.transaction(fn -> accept_locked(phase, items, prepared, definition) end)
    |> transaction_result()
  end

  defp accept_locked(phase, items, prepared, definition) do
    with %StudyExecution{} = execution <- ExecutionAccess.lock(phase.execution_id),
         %StudyPhase{} = locked <- lock_phase(phase.id),
         :ok <- require_collecting_final(execution),
         :ok <- require_final_phase(locked),
         :ok <- require_replica_zero(locked, items) do
      case link_or_create(locked, prepared, execution, definition) do
        {:ok, snapshot_id} -> snapshot_id
        {:error, %StudyError{} = error} -> Repo.rollback({:error, error})
      end
    else
      nil -> Repo.rollback({:error, StudyError.invalid_study_phase()})
      {:error, %StudyError{} = error} -> Repo.rollback({:error, error})
      {:stop, _state} = stop -> Repo.rollback(stop)
    end
  end

  defp transaction_result({:ok, snapshot_id}), do: {:ok, snapshot_id}
  defp transaction_result({:error, {:stop, state}}), do: {:stop, state}
  defp transaction_result({:error, {:error, %StudyError{} = error}}), do: {:error, error}
  defp transaction_result(_result), do: {:error, StudyError.final_snapshot_storage_failed()}

  # Cancellation and acceptance serialise on the execution row.
  defp require_collecting_final(%StudyExecution{state: :collecting_final}), do: :ok

  defp require_collecting_final(%StudyExecution{state: state}), do: {:stop, state}

  defp lock_phase(phase_id) do
    case Ecto.UUID.cast(phase_id) do
      {:ok, id} -> Repo.one(from phase in StudyPhase, where: phase.id == ^id, lock: "FOR UPDATE")
      :error -> nil
    end
  end

  defp link_or_create(
         %StudyPhase{snapshot_id: snapshot_id} = phase,
         _prepared,
         execution,
         definition
       )
       when is_binary(snapshot_id) do
    with {:ok, %EvidenceSnapshot{} = snapshot, _payload} <- load_existing(snapshot_id),
         :ok <- validate_existing(snapshot, phase, execution, definition) do
      {:ok, snapshot.id}
    else
      _invalid -> incomplete(["snapshot_id"])
    end
  end

  defp link_or_create(%StudyPhase{snapshot_id: nil}, :linked, _execution, _definition),
    do: incomplete(["snapshot_id"])

  defp link_or_create(
         %StudyPhase{} = phase,
         {:new, comparisons},
         %StudyExecution{} = execution,
         %Definition{} = definition
       ) do
    with {:ok, input} <- snapshot_input(execution, definition, comparisons),
         {:ok, snapshot} <- create_snapshot(input),
         {:ok, linked} <- link_snapshot(phase, snapshot.id) do
      {:ok, linked.snapshot_id}
    end
  end

  defp load_existing(snapshot_id), do: EvidenceSnapshots.load_final(snapshot_id)

  defp validate_existing(
         %EvidenceSnapshot{} = snapshot,
         %StudyPhase{} = _phase,
         %StudyExecution{} = execution,
         %Definition{} = definition
       ) do
    if snapshot.study_revision_id == execution.study_revision_id and
         snapshot.family_id == definition.family.id and
         snapshot.schema_version == definition.schema_version do
      :ok
    else
      incomplete(["snapshot_id"])
    end
  end

  defp reject_pilot_reuse(execution_id, items) do
    pilot_items =
      Repo.all(
        from item in StudyCollectionItem,
          join: phase in StudyPhase,
          on: phase.id == item.study_phase_id,
          where: phase.execution_id == ^execution_id and phase.phase == :pilot_collection
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
