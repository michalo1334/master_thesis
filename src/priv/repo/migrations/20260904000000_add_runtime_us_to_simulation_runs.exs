defmodule NetworkDefense.Repo.Migrations.AddRuntimeUsToSimulationRuns do
  use Ecto.Migration

  def change do
    alter table(:simulation_runs) do
      add :runtime_us, :bigint
    end

    create constraint(:simulation_runs, :simulation_runs_runtime_us_non_negative,
             check: "runtime_us IS NULL OR runtime_us >= 0"
           )
  end
end
