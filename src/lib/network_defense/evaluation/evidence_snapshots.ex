defmodule NetworkDefense.Evaluation.EvidenceSnapshots do
  @moduledoc false

  alias NetworkDefense.Evaluation.EvidenceSnapshot
  alias NetworkDefense.Evaluation.Final.Contracts.{FinalError, SnapshotInput}
  alias NetworkDefense.Evaluation.Final.Contracts.SnapshotPayload, as: FinalSnapshotPayload
  alias NetworkDefense.Evaluation.JsonBoundary

  alias NetworkDefense.Evaluation.Pilot.Contracts.{
    EvidenceSnapshotInput,
    PilotError,
    SnapshotPayload
  }

  alias NetworkDefense.Evaluation.Final.SnapshotLimits, as: FinalSnapshotLimits
  alias NetworkDefense.Evaluation.Pilot.{Limits, SnapshotLimits}

  alias NetworkDefense.Repo

  # Persistence for immutable Pilot evidence snapshots.
  #
  # Creation validates the whole document and its encoded size before one
  # insert. Reading trusts PostgreSQL row consistency and validates the stored
  # schema, metadata, and dimensions.

  @spec create(EvidenceSnapshotInput.t()) ::
          {:ok, EvidenceSnapshot.t()} | {:error, PilotError.t()}
  def create(%EvidenceSnapshotInput{} = input) do
    attrs = %{
      study_revision_id: input.study_revision_id,
      phase: input.phase,
      schema_version: input.schema_version,
      family_id: input.family_id,
      payload: SnapshotPayload.to_params(input.payload)
    }

    insert(attrs)
  end

  defp insert(attrs) do
    with {:ok, limits} <- Limits.fetch(),
         {:ok, encoded} <-
           JsonBoundary.encode(attrs.payload, fn _path ->
             PilotError.invalid_json_value(["payload"])
           end),
         :ok <- within_pilot_storage_limit(encoded, limits.snapshot_payload_bytes) do
      case Repo.insert(EvidenceSnapshot.create_changeset(%EvidenceSnapshot{}, attrs)) do
        {:ok, snapshot} ->
          {:ok, snapshot}

        {:error, _changeset} ->
          {:error,
           PilotError.workflow_failed("The evidence snapshot could not be stored safely.")}
      end
    end
  rescue
    _exception ->
      {:error, PilotError.workflow_failed("The evidence snapshot could not be stored safely.")}
  end

  defp within_pilot_storage_limit(encoded, limit) do
    bytes = IO.iodata_length(encoded)

    if bytes <= limit,
      do: :ok,
      else: {:error, PilotError.request_too_large(limit, bytes)}
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

  # Final snapshot persistence.
  #
  # The Final path repeats the Pilot guarantees with the Final contracts. A
  # Pilot snapshot cannot satisfy a Final read and a Final snapshot cannot
  # satisfy a Pilot read, because each read checks its own phase and evidence
  # role.

  @spec create_final(SnapshotInput.t()) ::
          {:ok, EvidenceSnapshot.t()} | {:error, FinalError.t()}
  def create_final(%SnapshotInput{} = input) do
    attrs = %{
      study_revision_id: input.study_revision_id,
      phase: input.phase,
      schema_version: input.schema_version,
      family_id: input.family_id,
      payload: FinalSnapshotPayload.to_params(input.payload)
    }

    with {:ok, inserted} <- insert_final(attrs),
         {:ok, stored, _payload} <- load_final(inserted.id) do
      {:ok, stored}
    end
  end

  # Creation returns the stored representation through the validated Final read
  # path. The caller receives the same JSONB representation as a later read.
  defp insert_final(attrs) do
    with {:ok, limits} <- FinalSnapshotLimits.limits(),
         {:ok, encoded} <-
           JsonBoundary.encode(attrs.payload, fn _path ->
             FinalError.invalid_json_value(["payload"])
           end),
         :ok <- within_final_storage_limit(encoded, limits.snapshot_payload_bytes) do
      case Repo.insert(EvidenceSnapshot.create_changeset(%EvidenceSnapshot{}, attrs)) do
        {:ok, snapshot} ->
          {:ok, snapshot}

        {:error, _changeset} ->
          {:error, FinalError.workflow_failed("The Final snapshot could not be stored safely.")}
      end
    end
  rescue
    _exception ->
      {:error, FinalError.workflow_failed("The Final snapshot could not be stored safely.")}
  end

  defp within_final_storage_limit(encoded, limit) do
    bytes = IO.iodata_length(encoded)

    if bytes <= limit,
      do: :ok,
      else: {:error, FinalError.request_too_large(limit, bytes)}
  end

  @spec get_final(String.t()) :: {:ok, EvidenceSnapshot.t()} | {:error, FinalError.t()}
  def get_final(snapshot_id) do
    with {:ok, snapshot, _payload} <- load_final(snapshot_id), do: {:ok, snapshot}
  end

  @spec load_final(String.t()) ::
          {:ok, EvidenceSnapshot.t(), FinalSnapshotPayload.t()} | {:error, FinalError.t()}
  def load_final(snapshot_id) do
    with {:ok, uuid} <- cast_final_uuid(snapshot_id) do
      case Repo.get(EvidenceSnapshot, uuid) do
        nil -> {:error, FinalError.snapshot_not_found()}
        %EvidenceSnapshot{} = snapshot -> validate_final_stored(snapshot)
      end
    end
  rescue
    _exception -> {:error, FinalError.snapshot_not_found()}
  end

  defp cast_final_uuid(snapshot_id) do
    case Ecto.UUID.cast(snapshot_id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, FinalError.snapshot_not_found()}
    end
  end

  defp validate_final_stored(%EvidenceSnapshot{} = snapshot) do
    with {:ok, payload} <- FinalSnapshotPayload.parse(snapshot.payload),
         :ok <- validate_final_metadata(snapshot, payload),
         :ok <- FinalSnapshotLimits.validate(payload) do
      {:ok, snapshot, payload}
    end
  end

  defp validate_final_metadata(%EvidenceSnapshot{} = snapshot, %FinalSnapshotPayload{} = payload) do
    cond do
      snapshot.phase != :final or payload.evidence_role != "final" ->
        {:error, FinalError.snapshot_phase_mismatch()}

      snapshot.schema_version != payload.schema_version ->
        {:error, FinalError.changed_snapshot("The stored snapshot schema versions disagree.")}

      not is_binary(snapshot.family_id) or snapshot.family_id == "" ->
        {:error, FinalError.changed_snapshot("The stored snapshot family ID is invalid.")}

      not uuid?(snapshot.study_revision_id) ->
        {:error, FinalError.changed_snapshot("The stored snapshot study revision is invalid.")}

      true ->
        :ok
    end
  end
end
