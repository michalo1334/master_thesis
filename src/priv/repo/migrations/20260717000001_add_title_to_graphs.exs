defmodule NetworkDefense.Repo.Migrations.AddTitleToGraphs do
  use Ecto.Migration

  def up do
    alter table(:graphs, primary_key: false) do
      add :title, :string, null: false, default: "Untitled Graph"
    end
  end
end
