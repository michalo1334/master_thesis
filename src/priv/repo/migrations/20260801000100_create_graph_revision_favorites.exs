defmodule NetworkDefense.Repo.Migrations.CreateGraphRevisionFavorites do
  use Ecto.Migration

  def change do
    create table(:graph_revision_favorites, primary_key: false) do
      add :graph_revision_id,
          references(:graph_revisions, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      timestamps(type: :utc_datetime)
    end
  end
end
