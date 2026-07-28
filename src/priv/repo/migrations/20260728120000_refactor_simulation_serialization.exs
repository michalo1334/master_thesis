defmodule NetworkDefense.Repo.Migrations.RefactorSimulationSerialization do
  use Ecto.Migration

  def up do
    execute("TRUNCATE TABLE experiments CASCADE")

    rename table(:experiments), :seed, to: :master_seed
    rename table(:simulation_runs), :initial_seed, to: :seed

    alter table(:experiments) do
      add :max_attempts, :integer, null: false, default: 1
      remove :run_count
      remove :initial_attacker_state
    end

    alter table(:simulation_runs) do
      remove :iteration_count
    end

    alter table(:iteration_steps) do
      remove :seed
      remove :successful_edge_ids
    end

    execute(
      "ALTER TABLE experiments RENAME CONSTRAINT experiments_seed_non_negative TO experiments_master_seed_non_negative"
    )

    execute(
      "ALTER TABLE simulation_runs RENAME CONSTRAINT simulation_runs_initial_seed_non_negative TO simulation_runs_seed_non_negative"
    )

    create constraint(:experiments, :experiments_max_attempts_positive, check: "max_attempts > 0")
  end

  def down do
    raise "simulation serialization refactor discards existing simulation history"
  end
end
