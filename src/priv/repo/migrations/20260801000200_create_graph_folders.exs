defmodule NetworkDefense.Repo.Migrations.CreateGraphFolders do
  use Ecto.Migration

  def change do
    create table(:graph_folders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    alter table(:graphs) do
      add :folder_id, references(:graph_folders, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:graphs, [:folder_id])
  end
end
