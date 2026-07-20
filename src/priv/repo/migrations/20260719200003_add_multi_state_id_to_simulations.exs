defmodule NetworkDefense.Repo.Migrations.AddMultiStateIdToSimulations do
  use Ecto.Migration

  def change do
    alter table(:simulations) do
      add :multi_state_id, references(:multi_states, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:simulations, [:multi_state_id])
  end
end
