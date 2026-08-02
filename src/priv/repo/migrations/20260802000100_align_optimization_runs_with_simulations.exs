defmodule NetworkDefense.Repo.Migrations.AlignOptimizationRunsWithSimulations do
  use Ecto.Migration

  def up do
    drop index(:optimization_runs, [:correlation_id])

    alter table(:optimization_runs) do
      remove :correlation_id
      remove :error
    end

    alter table(:optimization_actions) do
      remove :target_type
    end
  end

  def down do
    alter table(:optimization_runs) do
      add :correlation_id, :string, null: false, default: ""
      add :error, :string
    end

    create index(:optimization_runs, [:correlation_id])

    alter table(:optimization_actions) do
      add :target_type, :string, null: false, default: ""
    end
  end
end
