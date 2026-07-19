defmodule NetworkDefense.Repo.Migrations.CreateSimulations do
  use Ecto.Migration

  def change do
    create table(:simulations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :graph_id, references(:graphs, type: :binary_id, on_delete: :delete_all), null: false
      add :initial_seed, :bigint, null: false
      add :initial_attacker_state, :map, null: false
      add :iteration_count, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:simulations, [:graph_id])

    create constraint(:simulations, :simulations_initial_seed_non_negative,
             check: "initial_seed >= 0"
           )

    create constraint(:simulations, :simulations_iteration_count_positive,
             check: "iteration_count > 0"
           )
  end
end
