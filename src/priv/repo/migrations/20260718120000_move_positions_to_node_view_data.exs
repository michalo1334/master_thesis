defmodule NetworkDefense.Repo.Migrations.MovePositionsToNodeViewData do
  use Ecto.Migration

  def up do
    execute("DELETE FROM graphs")

    alter table(:nodes) do
      add :view_data, :map, null: false
    end

    alter table(:graphs) do
      remove :positions
    end
  end

  def down do
    alter table(:graphs) do
      add :positions, :map, null: false, default: %{}
    end

    alter table(:nodes) do
      remove :view_data
    end
  end
end
