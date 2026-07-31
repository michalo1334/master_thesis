defmodule NetworkDefense.Repo.Migrations.AddResumableSimulationProgress do
  use Ecto.Migration

  def up do
    alter table(:experiments) do
      add :total_trials, :integer, null: false, default: 0
      add :completed_trials, :integer, null: false, default: 0
      add :status, :string, null: false, default: "completed"
      add :initial_foothold_node_id, :binary_id
    end

    execute("""
    UPDATE experiments
    SET total_trials = counts.count, completed_trials = counts.count
    FROM (
      SELECT experiment_id, count(*)::integer AS count
      FROM simulation_runs
      GROUP BY experiment_id
    ) AS counts
    WHERE experiments.id = counts.experiment_id
    """)

    alter table(:simulation_runs) do
      add :trial_index, :integer, null: false, default: 0
    end

    execute("""
    UPDATE simulation_runs
    SET trial_index = numbered.trial_index
    FROM (
      SELECT id, row_number() OVER (PARTITION BY experiment_id ORDER BY seed)::integer AS trial_index
      FROM simulation_runs
    ) AS numbered
    WHERE simulation_runs.id = numbered.id
    """)

    create unique_index(:simulation_runs, [:experiment_id, :trial_index])
    create constraint(:experiments, :experiments_total_trials_positive, check: "total_trials > 0")

    create constraint(:experiments, :experiments_completed_trials_non_negative,
             check: "completed_trials >= 0 AND completed_trials <= total_trials"
           )

    create constraint(:experiments, :experiments_status_valid,
             check: "status IN ('running', 'failed', 'completed')"
           )
  end

  def down do
    drop constraint(:experiments, :experiments_status_valid)
    drop constraint(:experiments, :experiments_completed_trials_non_negative)
    drop constraint(:experiments, :experiments_total_trials_positive)
    drop unique_index(:simulation_runs, [:experiment_id, :trial_index])

    alter table(:simulation_runs) do
      remove :trial_index
    end

    alter table(:experiments) do
      remove :initial_foothold_node_id
      remove :status
      remove :completed_trials
      remove :total_trials
    end
  end
end
