defmodule NetworkDefense.Evaluation.EvidenceSnapshot do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias NetworkDefense.Evaluation.Pilot.CanonicalJson

  # Immutable normalized Pilot evidence snapshot.
  #
  # The payload is written once. `payload_bytes` is the canonical byte count of
  # that payload. Read paths compare the recomputed count with the stored count.
  # This detects a canonical byte-count change only. The design has no hash and
  # no update-prevention trigger, so two different payloads with the same
  # canonical size are not distinguishable here.

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "evaluation_evidence_snapshots" do
    field :study_revision_id, :binary_id
    field :phase, Ecto.Enum, values: [:pilot, :final]
    field :schema_version, :integer
    field :family_id, :string
    field :payload, :map
    field :payload_bytes, :integer

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{
          id: binary(),
          study_revision_id: binary(),
          phase: :pilot | :final,
          schema_version: integer(),
          family_id: String.t(),
          payload: map(),
          payload_bytes: pos_integer(),
          inserted_at: DateTime.t()
        }

  def create_changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :study_revision_id,
      :phase,
      :schema_version,
      :family_id,
      :payload,
      :payload_bytes
    ])
    |> validate_required([
      :study_revision_id,
      :phase,
      :schema_version,
      :family_id,
      :payload,
      :payload_bytes
    ])
    |> validate_number(:payload_bytes, greater_than: 0)
    |> validate_snapshot_payload()
  end

  defp validate_snapshot_payload(changeset) do
    payload = get_field(changeset, :payload)
    payload_bytes = get_field(changeset, :payload_bytes)

    if is_map(payload) and is_integer(payload_bytes) do
      case CanonicalJson.byte_size(payload) do
        {:ok, ^payload_bytes} ->
          changeset

        _different ->
          add_error(changeset, :payload_bytes, "does not match the canonical payload size")
      end
    else
      changeset
    end
  end
end
