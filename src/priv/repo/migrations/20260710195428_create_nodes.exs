defmodule NetworkDefense.Repo.Migrations.CreateNodes do
  use Ecto.Migration

  def change do
    create table(:nodes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :graph_id, references(:graphs, type: :binary_id, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :data, :map

      timestamps(type: :utc_datetime)
    end

    create index(:nodes, [:graph_id])
    create unique_index(:nodes, [:graph_id, :id])
  end
end
