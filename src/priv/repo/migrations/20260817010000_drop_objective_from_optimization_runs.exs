defmodule NetworkDefense.Repo.Migrations.DropObjectiveFromOptimizationRuns do
  use Ecto.Migration

  def up do
    drop constraint(:optimization_runs, :optimization_runs_objective_valid)

    alter table(:optimization_runs) do
      remove :objective
    end
  end

  def down do
    alter table(:optimization_runs) do
      add :objective, :string, null: false, default: "blast_radius"
    end

    create constraint(:optimization_runs, :optimization_runs_objective_valid,
             check: "objective IN ('blast_radius', 'mission_impact')"
           )
  end
end
