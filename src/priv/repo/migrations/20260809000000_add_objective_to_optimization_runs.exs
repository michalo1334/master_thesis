defmodule NetworkDefense.Repo.Migrations.AddObjectiveToOptimizationRuns do
  use Ecto.Migration

  def change do
    alter table(:optimization_runs) do
      add :objective, :string, null: false, default: "blast_radius"
    end

    create constraint(:optimization_runs, :optimization_runs_objective_valid,
             check: "objective IN ('blast_radius', 'mission_impact')"
           )
  end
end
