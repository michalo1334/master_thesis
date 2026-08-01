defmodule NetworkDefense.Repo.Migrations.RefactorGraphLineageToRevisions do
  use Ecto.Migration

  def up do
    execute(
      "TRUNCATE TABLE iteration_steps, simulation_runs, experiments, edges, nodes, graphs CASCADE"
    )

    alter table(:experiments) do
      remove :graph_id
      remove :lock_version
      add :graph_revision_id, :binary_id, null: false
    end

    alter table(:simulation_runs) do
      remove :graph_id
      add :graph_revision_id, :binary_id, null: false
    end

    drop table(:edges)
    drop table(:nodes)
    drop table(:graphs)

    create table(:graphs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      timestamps(type: :utc_datetime)
    end

    create table(:graph_revisions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :graph_id, references(:graphs, type: :binary_id, on_delete: :delete_all), null: false

      add :parent_revision_id, :binary_id

      add :number, :integer, null: false
      add :kind, :string, null: false
      add :title, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:graph_revisions, [:graph_id, :number])
    create unique_index(:graph_revisions, [:id, :graph_id])
    create constraint(:graph_revisions, :graph_revisions_number_positive, check: "number > 0")

    create constraint(:graph_revisions, :graph_revisions_kind_valid,
             check: "kind IN ('initial', 'edit', 'optimization')"
           )

    create constraint(:graph_revisions, :graph_revisions_parent_required,
             check:
               "(kind = 'initial' AND parent_revision_id IS NULL) OR (kind IN ('edit', 'optimization') AND parent_revision_id IS NOT NULL)"
           )

    execute("""
    ALTER TABLE graph_revisions
    ADD CONSTRAINT graph_revisions_parent_revision_graph_fkey
    FOREIGN KEY (parent_revision_id, graph_id)
    REFERENCES graph_revisions (id, graph_id)
    ON DELETE CASCADE
    """)

    create index(:graph_revisions, [:parent_revision_id])

    create table(:nodes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :graph_id, references(:graphs, type: :binary_id, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create index(:nodes, [:graph_id])
    create unique_index(:nodes, [:id, :graph_id])

    create table(:edges, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :graph_id, references(:graphs, type: :binary_id, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create index(:edges, [:graph_id])
    create unique_index(:edges, [:id, :graph_id])

    create table(:graph_revision_nodes, primary_key: false) do
      add :graph_id, :binary_id, null: false

      add :graph_revision_id,
          references(:graph_revisions,
            type: :binary_id,
            with: [graph_id: :graph_id],
            on_delete: :delete_all
          ),
          primary_key: true

      add :node_id,
          references(:nodes, type: :binary_id, with: [graph_id: :graph_id], on_delete: :restrict),
          primary_key: true

      add :type, :string, null: false
      add :data, :map
      add :view_data, :map, null: false
    end

    create index(:graph_revision_nodes, [:node_id])

    create table(:graph_revision_edges, primary_key: false) do
      add :graph_id, :binary_id, null: false

      add :graph_revision_id,
          references(:graph_revisions,
            type: :binary_id,
            with: [graph_id: :graph_id],
            on_delete: :delete_all
          ),
          primary_key: true

      add :edge_id,
          references(:edges, type: :binary_id, with: [graph_id: :graph_id], on_delete: :restrict),
          primary_key: true

      add :from_id,
          references(:nodes, type: :binary_id, with: [graph_id: :graph_id], on_delete: :restrict),
          null: false

      add :to_id,
          references(:nodes, type: :binary_id, with: [graph_id: :graph_id], on_delete: :restrict),
          null: false

      add :type, :string, null: false
      add :data, :map
    end

    create index(:graph_revision_edges, [:edge_id])

    execute("""
    ALTER TABLE graph_revision_edges
    ADD CONSTRAINT graph_revision_edges_from_revision_node_fkey
    FOREIGN KEY (graph_revision_id, from_id)
    REFERENCES graph_revision_nodes (graph_revision_id, node_id)
    ON DELETE CASCADE
    """)

    execute("""
    ALTER TABLE graph_revision_edges
    ADD CONSTRAINT graph_revision_edges_to_revision_node_fkey
    FOREIGN KEY (graph_revision_id, to_id)
    REFERENCES graph_revision_nodes (graph_revision_id, node_id)
    ON DELETE CASCADE
    """)

    execute("""
    CREATE FUNCTION prevent_graph_snapshot_update()
    RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'graph snapshots are immutable';
    END;
    $$ LANGUAGE plpgsql
    """)

    for table <- ["graph_revisions", "graph_revision_nodes", "graph_revision_edges"] do
      execute("""
      CREATE TRIGGER #{table}_immutable
      BEFORE UPDATE ON #{table}
      FOR EACH ROW EXECUTE FUNCTION prevent_graph_snapshot_update()
      """)
    end

    alter table(:experiments) do
      modify :graph_revision_id,
             references(:graph_revisions, type: :binary_id, on_delete: :delete_all),
             null: false
    end

    create index(:experiments, [:graph_revision_id])
    create unique_index(:experiments, [:id, :graph_revision_id])

    alter table(:simulation_runs) do
      modify :graph_revision_id,
             references(:graph_revisions, type: :binary_id, on_delete: :delete_all),
             null: false
    end

    create index(:simulation_runs, [:graph_revision_id])

    drop constraint(:simulation_runs, :simulation_runs_experiment_id_fkey)

    execute("""
    ALTER TABLE simulation_runs
    ADD CONSTRAINT simulation_runs_experiment_revision_fkey
    FOREIGN KEY (experiment_id, graph_revision_id)
    REFERENCES experiments (id, graph_revision_id)
    ON DELETE CASCADE
    """)
  end

  def down do
    raise "graph lineage clean-slate migration is irreversible"
  end
end
