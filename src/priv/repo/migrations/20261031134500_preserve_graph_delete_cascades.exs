defmodule NetworkDefense.Repo.Migrations.PreserveGraphDeleteCascades do
  use Ecto.Migration

  # Snapshot references restrict identity deletion. Remove revisions first when
  # deleting their graph, so the existing identity cascades can then complete.
  # Keep immediate membership checks and snapshot immutability unchanged.
  def change do
    execute(
      """
      CREATE FUNCTION delete_graph_revisions_before_graph() RETURNS trigger
      LANGUAGE plpgsql AS $$
      BEGIN
        DELETE FROM graph_revisions WHERE graph_id = OLD.id;
        RETURN OLD;
      END;
      $$;
      """,
      "DROP FUNCTION delete_graph_revisions_before_graph()"
    )

    execute(
      """
      CREATE TRIGGER graphs_delete_revisions_first
        BEFORE DELETE ON graphs
        FOR EACH ROW EXECUTE FUNCTION delete_graph_revisions_before_graph()
      """,
      "DROP TRIGGER graphs_delete_revisions_first ON graphs"
    )
  end
end
