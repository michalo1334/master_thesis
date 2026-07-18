defmodule NetworkDefense.Repo.Migrations.AddLockVersionToGraphs do
  use Ecto.Migration

  def change do
    alter table(:graphs) do
      add :lock_version, :integer, null: false, default: 1
    end
  end
end
