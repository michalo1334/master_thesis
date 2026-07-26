defmodule NetworkDefense.Repo.Migrations.AddLineageToGraphs do
  use Ecto.Migration

  def change do
    alter table(:graphs) do
      add :parent_id, references(:graphs, type: :binary_id, on_delete: :nilify_all)
      add :source, :string
    end
  end
end
