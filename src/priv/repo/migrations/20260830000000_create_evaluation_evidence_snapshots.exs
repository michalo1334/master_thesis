defmodule NetworkDefense.Repo.Migrations.CreateEvaluationEvidenceSnapshots do
  use Ecto.Migration

  def change do
    create table(:evaluation_evidence_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :study_revision_id, :binary_id, null: false
      add :phase, :string, null: false
      add :schema_version, :integer, null: false
      add :family_id, :string, null: false
      add :payload, :map, null: false
      add :payload_bytes, :integer, null: false

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create constraint(:evaluation_evidence_snapshots, :evaluation_evidence_snapshots_phase_valid,
             check: "phase IN ('pilot', 'final')"
           )

    create constraint(
             :evaluation_evidence_snapshots,
             :evaluation_evidence_snapshots_schema_version_valid,
             check: "schema_version = 1"
           )

    create constraint(
             :evaluation_evidence_snapshots,
             :evaluation_evidence_snapshots_payload_bytes_positive,
             check: "payload_bytes > 0"
           )

    create index(:evaluation_evidence_snapshots, [:study_revision_id, :family_id, :phase])
  end
end
