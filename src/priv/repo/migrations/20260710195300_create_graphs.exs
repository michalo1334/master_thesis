defmodule NetworkDefense.Repo.Migrations.CreateGraphs do
  use Ecto.Migration

  def change do
    create table(:graphs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      timestamps(type: :utc_datetime)
    end
  end
end
