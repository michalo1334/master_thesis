defmodule NetworkDefense.Repo.Migrations.CreateMultiStates do
  use Ecto.Migration

  def change do
    create table(:multi_states, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :graph_id, references(:graphs, type: :binary_id, on_delete: :delete_all), null: false
      add :seed, :bigint, null: false
      add :iteration_count, :integer, null: false
      add :initial_attacker_state, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:multi_states, [:graph_id])

    create constraint(:multi_states, :multi_states_seed_non_negative, check: "seed >= 0")

    create constraint(:multi_states, :multi_states_iteration_count_positive,
             check: "iteration_count > 0"
           )
  end
end
