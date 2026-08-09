defmodule NetworkDefense.Repo.Migrations.AddReproducibilityInputsToOptimizationRuns do
  use Ecto.Migration

  def change do
    alter table(:optimization_runs) do
      add :seed, :bigint
      add :simulation_config, :map
    end
  end
end
