defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.Snapshot do
  @moduledoc false

  import Ecto.Query

  alias NetworkDefense.Evaluation.EvidenceSnapshots

  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Error, as: PilotError

  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.Evidence.Contracts.{
    ComparisonEvidence,
    RuntimeEvidence
  }

  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.Snapshot.Contracts.{
    Input,
    Payload
  }

  alias NetworkDefense.Evaluation.Study.Contracts.Definition
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.EvidenceAssembler
  alias NetworkDefense.Evaluation.Study.Pipeline.ExecutionAccess
  alias NetworkDefense.Evaluation.{StudyCollectionItem, StudyExecution, StudyPhase}
  alias NetworkDefense.Repo

  @collection_phase :pilot_collection
  @replica_position 0
  @evidence_role "pilot"

  @spec assemble_and_store_pilot_snapshot(
          StudyPhase.t(),
          [StudyCollectionItem.t()],
          Definition.t()
        ) ::
          {:ok, String.t()} | {:error, StudyError.t()}
  def assemble_and_store_pilot_snapshot(
        %StudyPhase{} = phase,
        collection_items,
        %Definition{} = definition
      )
      when is_list(collection_items) do
    with {:ok, item_ids} <- collection_item_ids(collection_items) do
      checkpoint(phase.id, item_ids, definition)
    end
  end

  def assemble_and_store_pilot_snapshot(_phase, _collection_items, _definition),
    do: incomplete(["collection_items"])

  @doc false
  @spec assemble_evidence(StudyPhase.t(), [StudyCollectionItem.t()], Definition.t()) ::
          {:ok, {[ComparisonEvidence.t()], [EvidenceAssembler.item_evidence()]}}
          | {:error, StudyError.t()}
  def assemble_evidence(%StudyPhase{} = phase, collection_items, %Definition{} = definition)
      when is_list(collection_items) do
    EvidenceAssembler.assemble(phase, collection_items, definition,
      replica_position: @replica_position,
      incomplete: &StudyError.incomplete_pilot_evidence/1
    )
  end

  def assemble_evidence(_phase, _collection_items, _definition),
    do: incomplete(["collection_items"])

  defp checkpoint(phase_id, item_ids, definition) do
    result =
      Repo.transaction(fn ->
        case lock_phase(phase_id) do
          nil -> Repo.rollback({:error, StudyError.invalid_study_phase()})
          %StudyPhase{} = locked -> link_or_create(locked, item_ids, definition)
        end
      end)

    case result do
      {:ok, {:ok, snapshot_id}} -> {:ok, snapshot_id}
      {:error, {:error, %StudyError{} = error}} -> {:error, error}
    end
  end

  defp lock_phase(phase_id) do
    case cast_id(phase_id) do
      {:ok, id} -> Repo.one(from phase in StudyPhase, where: phase.id == ^id, lock: "FOR UPDATE")
      :error -> nil
    end
  end

  defp link_or_create(
         %StudyPhase{phase: @collection_phase, snapshot_id: snapshot_id},
         _item_ids,
         _definition
       )
       when is_binary(snapshot_id),
       do: {:ok, snapshot_id}

  defp link_or_create(%StudyPhase{phase: @collection_phase} = phase, item_ids, definition) do
    case assemble(phase, item_ids, definition) do
      {:ok, input} -> create_and_link(phase, input)
      {:error, %StudyError{} = error} -> Repo.rollback({:error, error})
    end
  end

  defp link_or_create(%StudyPhase{phase: phase}, _item_ids, _definition),
    do: Repo.rollback({:error, StudyError.unsupported_collection_phase(phase)})

  defp create_and_link(%StudyPhase{} = phase, %Input{} = input) do
    case EvidenceSnapshots.create(input) do
      {:ok, snapshot} ->
        link(phase, snapshot.id)

      {:error, %PilotError{}} ->
        Repo.rollback({:error, StudyError.pilot_snapshot_storage_failed()})
    end
  end

  defp link(%StudyPhase{} = phase, snapshot_id) do
    case phase |> StudyPhase.changeset(%{snapshot_id: snapshot_id}) |> Repo.update() do
      {:ok, %StudyPhase{} = linked} -> {:ok, linked.snapshot_id}
      {:error, _changeset} -> Repo.rollback({:error, StudyError.pilot_snapshot_storage_failed()})
    end
  end

  defp assemble(%StudyPhase{} = phase, item_ids, %Definition{} = definition) do
    items = reload_items!(item_ids)

    with {:ok, execution} <- load_execution(phase.execution_id),
         {:ok, {comparisons, evidence}} <- assemble_evidence(phase, items, definition) do
      input(execution, definition, payload(comparisons, evidence, definition))
    end
  end

  defp reload_items!(item_ids) do
    Repo.all(from item in StudyCollectionItem, where: item.id in ^item_ids)
  end

  # The snapshot input needs the stored revision of the owning execution, so the
  # boundary keeps its own bounded lookup.
  defp collection_item_ids(collection_items) do
    case EvidenceAssembler.collection_item_ids(collection_items) do
      {:ok, ids} -> {:ok, ids}
      {:error, path} -> incomplete(path)
    end
  end

  defp load_execution(execution_id) do
    case ExecutionAccess.fetch_trusted(execution_id) do
      {:ok, %StudyExecution{} = execution} -> {:ok, execution}
      {:error, _error} -> {:error, StudyError.invalid_study_phase()}
    end
  end

  defp cast_id(value), do: Ecto.UUID.cast(value)

  defp payload(comparisons, evidence, %Definition{} = definition) do
    %Payload{
      schema_version: definition.schema_version,
      evidence_role: @evidence_role,
      comparisons: comparisons,
      runtime_evidence: runtime_evidence(evidence, definition)
    }
  end

  defp runtime_evidence(evidence, %Definition{} = definition) do
    %RuntimeEvidence{
      plan_selection_ms: Enum.map(evidence, &milliseconds(&1.optimization.runtime_ms)),
      attack_trial_ms:
        Enum.flat_map(evidence, fn item ->
          Enum.map(item.runs, fn run -> run.runtime_us / 1000 end)
        end),
      tier_count: definition.family.comparisons |> Enum.map(& &1.tier) |> Enum.uniq() |> length(),
      strategy_group_count: strategy_group_count(definition)
    }
  end

  defp strategy_group_count(%Definition{} = definition) do
    definition.family.comparisons
    |> Enum.flat_map(fn comparison ->
      [
        {comparison.tier, comparison.budget, comparison.alternative},
        {comparison.tier, comparison.budget, comparison.reference}
      ]
    end)
    |> Enum.uniq()
    |> length()
  end

  defp milliseconds(value) when is_integer(value), do: value * 1.0

  defp input(%StudyExecution{} = execution, %Definition{} = definition, payload) do
    input = %Input{
      study_revision_id: execution.study_revision_id,
      phase: @evidence_role,
      schema_version: definition.schema_version,
      family_id: definition.family.id,
      payload: payload
    }

    case input |> Input.to_params() |> Input.parse() do
      {:ok, parsed} -> {:ok, parsed}
      {:error, %PilotError{}} -> incomplete(["payload"])
    end
  end

  defp incomplete(path), do: {:error, StudyError.incomplete_pilot_evidence(path)}
end
