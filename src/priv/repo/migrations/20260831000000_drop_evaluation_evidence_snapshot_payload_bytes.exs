defmodule NetworkDefense.Repo.Migrations.DropEvaluationEvidenceSnapshotPayloadBytes do
  use Ecto.Migration

  def change do
    alter table(:evaluation_evidence_snapshots) do
      remove_if_exists :payload_bytes, :integer
    end
  end
end
