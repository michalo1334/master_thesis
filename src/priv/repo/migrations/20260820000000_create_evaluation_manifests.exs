defmodule NetworkDefense.Repo.Migrations.CreateEvaluationManifests do
  use Ecto.Migration

  def change do
    create table(:evaluation_manifests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :manifest_id, :string, null: false
      add :title, :string, null: false
      add :content, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:evaluation_manifests, [:manifest_id])

    create table(:evaluation_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :evaluation_manifest_id,
          references(:evaluation_manifests, type: :binary_id, on_delete: :delete_all),
          null: false

      add :source_graph_revision_id,
          references(:graph_revisions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :resolved_manifest, :map, null: false
      add :status, :string, null: false, default: "running"
      add :failure_reason, :string

      timestamps(type: :utc_datetime)
    end

    create index(:evaluation_runs, [:evaluation_manifest_id])
    create index(:evaluation_runs, [:source_graph_revision_id])

    create constraint(:evaluation_runs, :evaluation_runs_status_valid,
             check: "status IN ('running', 'completed', 'failed')"
           )

    alter table(:optimization_runs) do
      add :evaluation_run_id,
          references(:evaluation_runs, type: :binary_id, on_delete: :delete_all)

      add :selection_seed, :bigint
    end

    create index(:optimization_runs, [:evaluation_run_id])

    create constraint(:optimization_runs, :optimization_runs_evaluation_selection_seed_required,
             check: "evaluation_run_id IS NULL OR selection_seed IS NOT NULL"
           )

    create unique_index(
             :optimization_runs,
             [
               :evaluation_run_id,
               :strategy,
               :requested_budget,
               :selection_seed
             ],
             name: :optimization_runs_evaluation_plan_unique,
             where: "evaluation_run_id IS NOT NULL AND selection_seed IS NOT NULL"
           )

    alter table(:experiments) do
      add :evaluation_run_id,
          references(:evaluation_runs, type: :binary_id, on_delete: :delete_all)

      add :optimization_run_id,
          references(:optimization_runs, type: :binary_id, on_delete: :delete_all)
    end

    create index(:experiments, [:evaluation_run_id])
    create index(:experiments, [:optimization_run_id])

    create unique_index(:experiments, [:evaluation_run_id, :optimization_run_id],
             name: :experiments_evaluation_run_optimization_unique,
             where: "optimization_run_id IS NOT NULL"
           )

    create unique_index(:experiments, [:evaluation_run_id],
             name: :experiments_evaluation_run_baseline_unique,
             where: "optimization_run_id IS NULL"
           )
  end
end
