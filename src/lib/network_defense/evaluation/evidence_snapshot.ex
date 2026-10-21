defmodule NetworkDefense.Evaluation.EvidenceSnapshot do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  # Immutable normalized evaluation evidence snapshot.
  #
  # The application validates a complete payload before it inserts one row.
  # Persisted PostgreSQL rows are the trusted storage boundary on read.

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "evaluation_evidence_snapshots" do
    field :study_revision_id, :binary_id
    field :phase, Ecto.Enum, values: [:pilot, :final]
    field :schema_version, :integer
    field :family_id, :string
    field :payload, :map

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{
          id: binary(),
          study_revision_id: binary(),
          phase: :pilot | :final,
          schema_version: integer(),
          family_id: String.t(),
          payload: map(),
          inserted_at: DateTime.t()
        }

  def create_changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :study_revision_id,
      :phase,
      :schema_version,
      :family_id,
      :payload
    ])
    |> validate_required([
      :study_revision_id,
      :phase,
      :schema_version,
      :family_id,
      :payload
    ])
  end
end
