defmodule NetworkDefense.Repo.Migrations.AddAnalysisToArtifacts do
  use Ecto.Migration

  def change do
    alter table(:graph_revisions) do
      add :analysis_id, references(:workflow_runs, type: :binary_id, on_delete: :nilify_all)
    end

    alter table(:experiments) do
      add :analysis_id, references(:workflow_runs, type: :binary_id, on_delete: :nilify_all)
    end

    alter table(:optimization_runs) do
      add :analysis_id, references(:workflow_runs, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:graph_revisions, [:analysis_id])
    create index(:experiments, [:analysis_id])
    create index(:optimization_runs, [:analysis_id])
  end
end
