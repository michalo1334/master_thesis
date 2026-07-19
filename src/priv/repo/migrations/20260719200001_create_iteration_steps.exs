defmodule NetworkDefense.Repo.Migrations.CreateIterationSteps do
  use Ecto.Migration

  def change do
    create table(:iteration_steps, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :simulation_id, references(:simulations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :index, :integer, null: false
      add :attempted_action, :map
      add :success, :boolean, null: false
      add :attacker_state, :map, null: false
      add :seed, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:iteration_steps, [:simulation_id, :index])

    create constraint(:iteration_steps, :iteration_steps_index_positive, check: "index > 0")
  end
end
