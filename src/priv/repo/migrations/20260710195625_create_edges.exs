defmodule NetworkDefense.Repo.Migrations.CreateEdges do
  use Ecto.Migration

  def change do
    create table(:edges, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :data, :map

      add :graph_id, references(:graphs, type: :binary_id, on_delete: :delete_all), null: false

      add :from_id,
          references(:nodes,
            type: :binary_id,
            with: [graph_id: :graph_id],
            name: :edges_from_graph_fkey,
            on_delete: :delete_all
          ),
          null: false

      add :to_id,
          references(:nodes,
            type: :binary_id,
            with: [graph_id: :graph_id],
            name: :edges_to_graph_fkey,
            on_delete: :delete_all
          ),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:edges, [:graph_id])
    create index(:edges, [:graph_id, :from_id])
    create index(:edges, [:graph_id, :to_id])
  end
end
