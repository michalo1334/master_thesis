defmodule NetworkDefense.Repo.Migrations.CreateEvaluationStudyRevisions do
  use Ecto.Migration

  def change do
    create table(:evaluation_study_revisions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :study_id, :string, null: false
      add :revision, :integer, null: false
      add :schema_version, :integer, null: false
      add :definition, :map, null: false

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create index(:evaluation_study_revisions, [:study_id, :revision], unique: true)
  end
end
