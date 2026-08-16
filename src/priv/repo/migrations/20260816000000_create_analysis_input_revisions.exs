defmodule NetworkDefense.Repo.Migrations.CreateAnalysisInputRevisions do
  use Ecto.Migration

  def up do
    create table(:analysis_input_revisions, primary_key: false) do
      add :workflow_run_id,
          references(:workflow_runs, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :graph_revision_id,
          references(:graph_revisions, type: :binary_id, on_delete: :delete_all),
          primary_key: true
    end

    create index(:analysis_input_revisions, [:graph_revision_id])

    execute("""
    INSERT INTO analysis_input_revisions (workflow_run_id, graph_revision_id)
    SELECT workflow_runs.id, graph_revisions.id
    FROM workflow_runs
    JOIN graph_revisions
      ON graph_revisions.id::text = workflow_runs.input->>'graph_revision_id'
    ON CONFLICT DO NOTHING
    """)
  end

  def down do
    drop table(:analysis_input_revisions)
  end
end
