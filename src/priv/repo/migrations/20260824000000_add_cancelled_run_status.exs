defmodule NetworkDefense.Repo.Migrations.AddCancelledRunStatus do
  use Ecto.Migration

  def change do
    alter table(:experiments) do
      modify :status, :string, null: false, default: "running"
    end

    drop constraint(:experiments, :experiments_status_valid)
    drop constraint(:evaluation_runs, :evaluation_runs_status_valid)

    create constraint(:experiments, :experiments_status_valid,
             check: "status IN ('running', 'failed', 'completed', 'cancelled')"
           )

    create constraint(:evaluation_runs, :evaluation_runs_status_valid,
             check: "status IN ('running', 'completed', 'failed', 'cancelled')"
           )

    create constraint(:optimization_runs, :optimization_runs_status_valid,
             check: "status IN ('running', 'completed', 'failed', 'cancelled')"
           )
  end
end
