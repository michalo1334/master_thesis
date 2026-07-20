defmodule NetworkDefense.Repo.Migrations.AddLockVersionAndRuntimeToMultiStates do
  use Ecto.Migration

  def change do
    alter table(:multi_states) do
      add :lock_version, :integer, null: false, default: 1
      add :runtime_ms, :integer, null: false, default: 0
      add :simulation_count, :integer, null: false, default: 1
    end
  end
end
