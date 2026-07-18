defmodule NetworkDefense.Repo.Migrations.AddPositionsToGraphs do
  use Ecto.Migration

  def change do
    alter table(:graphs) do
      add :positions, :map, null: false, default: %{}
    end
  end
end
