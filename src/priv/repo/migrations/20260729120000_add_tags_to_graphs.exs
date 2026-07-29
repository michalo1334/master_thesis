defmodule NetworkDefense.Repo.Migrations.AddTagsToGraphs do
  use Ecto.Migration

  def up do
    alter table(:graphs) do
      add :tags, {:array, :string}, null: false, default: ["original"]
    end

    execute("""
    UPDATE graphs
    SET tags = CASE
      WHEN source = 'optimization' THEN ARRAY['optimization']
      ELSE ARRAY['original']
    END
    """)
  end

  def down do
    alter table(:graphs) do
      remove :tags
    end
  end
end
