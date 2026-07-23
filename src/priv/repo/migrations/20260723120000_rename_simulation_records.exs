defmodule NetworkDefense.Repo.Migrations.RenameSimulationRecords do
  use Ecto.Migration

  def up do
    rename table(:simulations), to: table(:simulation_runs)
    rename table(:multi_states), to: table(:experiments)
    rename table(:simulation_runs), :multi_state_id, to: :experiment_id
    rename table(:iteration_steps), :simulation_id, to: :run_id
    rename table(:experiments), :simulation_count, to: :run_count

    rename_constraint(
      :simulation_runs,
      :simulations_graph_id_fkey,
      :simulation_runs_graph_id_fkey
    )

    rename_constraint(
      :simulation_runs,
      :simulations_multi_state_id_fkey,
      :simulation_runs_experiment_id_fkey
    )

    rename_constraint(:experiments, :multi_states_graph_id_fkey, :experiments_graph_id_fkey)

    rename_constraint(
      :iteration_steps,
      :iteration_steps_simulation_id_fkey,
      :iteration_steps_run_id_fkey
    )

    rename_constraint(
      :simulation_runs,
      :simulations_initial_seed_non_negative,
      :simulation_runs_initial_seed_non_negative
    )

    rename_constraint(
      :experiments,
      :multi_states_seed_non_negative,
      :experiments_seed_non_negative
    )

    rename_constraint(
      :experiments,
      :multi_states_iteration_count_positive,
      :experiments_iteration_count_positive
    )

    rename_index(:simulation_runs, :simulations_graph_id_index, :simulation_runs_graph_id_index)

    rename_index(
      :simulation_runs,
      :simulations_multi_state_id_index,
      :simulation_runs_experiment_id_index
    )

    rename_index(:experiments, :multi_states_graph_id_index, :experiments_graph_id_index)

    rename_index(
      :iteration_steps,
      :iteration_steps_simulation_id_index_index,
      :iteration_steps_run_id_index_index
    )
  end

  def down do
    rename_index(:simulation_runs, :simulation_runs_graph_id_index, :simulations_graph_id_index)

    rename_index(
      :simulation_runs,
      :simulation_runs_experiment_id_index,
      :simulations_multi_state_id_index
    )

    rename_index(:experiments, :experiments_graph_id_index, :multi_states_graph_id_index)

    rename_index(
      :iteration_steps,
      :iteration_steps_run_id_index_index,
      :iteration_steps_simulation_id_index_index
    )

    rename_constraint(
      :simulation_runs,
      :simulation_runs_graph_id_fkey,
      :simulations_graph_id_fkey
    )

    rename_constraint(
      :simulation_runs,
      :simulation_runs_experiment_id_fkey,
      :simulations_multi_state_id_fkey
    )

    rename_constraint(:experiments, :experiments_graph_id_fkey, :multi_states_graph_id_fkey)

    rename_constraint(
      :iteration_steps,
      :iteration_steps_run_id_fkey,
      :iteration_steps_simulation_id_fkey
    )

    rename_constraint(
      :simulation_runs,
      :simulation_runs_initial_seed_non_negative,
      :simulations_initial_seed_non_negative
    )

    rename_constraint(
      :experiments,
      :experiments_seed_non_negative,
      :multi_states_seed_non_negative
    )

    rename_constraint(
      :experiments,
      :experiments_iteration_count_positive,
      :multi_states_iteration_count_positive
    )

    rename table(:experiments), :run_count, to: :simulation_count
    rename table(:iteration_steps), :run_id, to: :simulation_id
    rename table(:simulation_runs), :experiment_id, to: :multi_state_id
    rename table(:experiments), to: table(:multi_states)
    rename table(:simulation_runs), to: table(:simulations)
  end

  defp rename_constraint(table, from, to) do
    execute("ALTER TABLE #{table} RENAME CONSTRAINT #{from} TO #{to}")
  end

  defp rename_index(_table, from, to) do
    execute("ALTER INDEX #{from} RENAME TO #{to}")
  end
end
