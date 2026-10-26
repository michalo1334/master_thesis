defmodule NetworkDefense.Repo.Migrations.AddReproducibilityInputsToOptimizationRuns do
  use Ecto.Migration

  def change do
    alter table(:optimization_runs) do
      add :seed, :bigint
      add :execution_config, :map, null: false
    end
  end
end
