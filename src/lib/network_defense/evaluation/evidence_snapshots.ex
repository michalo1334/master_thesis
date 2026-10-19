defmodule NetworkDefense.Evaluation.EvidenceSnapshots do
  @moduledoc false

  alias NetworkDefense.Evaluation.EvidenceSnapshot
  alias NetworkDefense.Evaluation.Pilot.CanonicalJson

  alias NetworkDefense.Evaluation.Pilot.Contracts.{
    EvidenceSnapshotInput,
    PilotError,
    SnapshotPayload
  }

  alias NetworkDefense.Evaluation.Pilot.SnapshotLimits

  alias NetworkDefense.Repo

  # Persistence for immutable Pilot evidence snapshots.
  #
  # Creation validates the whole document before one insert. Reading validates
  # the stored payload and compares its canonical byte count with the stored
  # count. The count detects a size change only; there is no content hash.

  @spec create(EvidenceSnapshotInput.t()) ::
          {:ok, EvidenceSnapshot.t()} | {:error, PilotError.t()}
  def create(%EvidenceSnapshotInput{} = input) do
    attrs = %{
      study_revision_id: input.study_revision_id,
      phase: input.phase,
      schema_version: input.schema_version,
      family_id: input.family_id,
      payload: SnapshotPayload.to_params(input.payload),
      payload_bytes: input.payload_bytes
    }

    case Repo.insert(EvidenceSnapshot.create_changeset(%EvidenceSnapshot{}, attrs)) do
      {:ok, snapshot} ->
        {:ok, snapshot}

      {:error, _changeset} ->
        {:error, PilotError.workflow_failed("The evidence snapshot could not be stored safely.")}
    end
  rescue
    _exception ->
      {:error, PilotError.workflow_failed("The evidence snapshot could not be stored safely.")}
  end

  @spec get(String.t()) :: {:ok, EvidenceSnapshot.t()} | {:error, PilotError.t()}
  def get(snapshot_id) do
    with {:ok, snapshot, _payload} <- load(snapshot_id), do: {:ok, snapshot}
  end

  @spec load(String.t()) ::
          {:ok, EvidenceSnapshot.t(), SnapshotPayload.t()} | {:error, PilotError.t()}
  def load(snapshot_id) do
    with {:ok, uuid} <- cast_uuid(snapshot_id) do
      case Repo.get(EvidenceSnapshot, uuid) do
        nil -> {:error, PilotError.snapshot_not_found()}
        %EvidenceSnapshot{} = snapshot -> validate_stored(snapshot)
      end
    end
  rescue
    _exception -> {:error, PilotError.snapshot_not_found()}
  end

  defp cast_uuid(snapshot_id) do
    case Ecto.UUID.cast(snapshot_id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, PilotError.snapshot_not_found()}
    end
  end

  defp validate_stored(%EvidenceSnapshot{} = snapshot) do
    with {:ok, payload} <- SnapshotPayload.parse(snapshot.payload),
         :ok <- validate_metadata(snapshot, payload),
         :ok <- validate_bytes(snapshot, payload),
         :ok <- SnapshotLimits.validate(payload) do
      {:ok, snapshot, payload}
    end
  end

  defp validate_metadata(%EvidenceSnapshot{} = snapshot, %SnapshotPayload{} = payload) do
    cond do
      snapshot.phase != :pilot or payload.evidence_role != "pilot" ->
        {:error,
         PilotError.snapshot_phase_mismatch("The stored snapshot is not a Pilot snapshot.")}

      snapshot.schema_version != payload.schema_version ->
        {:error, PilotError.changed_snapshot("The stored snapshot schema versions disagree.")}

      not is_binary(snapshot.family_id) or snapshot.family_id == "" ->
        {:error, PilotError.changed_snapshot("The stored snapshot family ID is invalid.")}

      not uuid?(snapshot.study_revision_id) ->
        {:error, PilotError.changed_snapshot("The stored snapshot study revision is invalid.")}

      true ->
        :ok
    end
  end

  defp uuid?(value) when is_binary(value),
    do: match?({:ok, _uuid}, Ecto.UUID.cast(value))

  defp uuid?(_value), do: false

  defp validate_bytes(%EvidenceSnapshot{} = snapshot, %SnapshotPayload{} = payload) do
    case CanonicalJson.byte_size(SnapshotPayload.to_params(payload)) do
      {:ok, bytes} when bytes == snapshot.payload_bytes ->
        :ok

      _different ->
        {:error, PilotError.changed_snapshot("The stored snapshot byte count changed.")}
    end
  end
end
