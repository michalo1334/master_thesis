defmodule NetworkDefense.Repo.Migrations.RenameAnalysisInputRevisions do
  use Ecto.Migration

  def up do
    rename table(:analysis_input_revisions), to: table(:analysis_graph_revisions)

    execute(
      "ALTER INDEX analysis_input_revisions_graph_revision_id_index RENAME TO analysis_graph_revisions_graph_revision_id_index"
    )

    execute("""
    INSERT INTO analysis_graph_revisions (workflow_run_id, graph_revision_id)
    SELECT analysis_id, id
    FROM graph_revisions
    WHERE analysis_id IS NOT NULL
    ON CONFLICT DO NOTHING
    """)

    drop index(:graph_revisions, [:analysis_id])

    alter table(:graph_revisions) do
      remove :analysis_id
    end
  end

  def down do
    alter table(:graph_revisions) do
      add :analysis_id, references(:workflow_runs, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:graph_revisions, [:analysis_id])

    execute("""
    UPDATE graph_revisions AS revision
    SET analysis_id = grouped.workflow_run_id
    FROM (
      SELECT DISTINCT ON (graph_revision_id) graph_revision_id, workflow_run_id
      FROM analysis_graph_revisions
      ORDER BY graph_revision_id, workflow_run_id
    ) AS grouped
    WHERE revision.id = grouped.graph_revision_id
    """)

    execute(
      "ALTER INDEX analysis_graph_revisions_graph_revision_id_index RENAME TO analysis_input_revisions_graph_revision_id_index"
    )

    rename table(:analysis_graph_revisions), to: table(:analysis_input_revisions)
  end
end
