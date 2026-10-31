defmodule NetworkDefense.Evaluation2.SetupTest do
  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Graph.{Graph, Graphs}
  alias NetworkDefense.Topology.EnterpriseTopology

  @moduletag :integration
  @moduletag case_id: "SETUP-01"

  test "WHEN a referenced identity is deleted directly THEN snapshot protection remains active" do
    {:ok, graph} =
      Graphs.insert(EnterpriseTopology.generate(title: "protected identities", hosts: 8, seed: 1))

    node = hd(Graph.nodes(graph))
    edge = hd(Graph.edges(graph))

    for {table, id} <- [{"nodes", node.id}, {"edges", edge.id}] do
      {:ok, id} = Ecto.UUID.dump(id)

      assert {:error, %Postgrex.Error{postgres: %{code: code}}} =
               Repo.query("DELETE FROM #{table} WHERE id = $1", [id], mode: :savepoint)

      assert code in [:foreign_key_violation, :restrict_violation]
    end

    assert %Graph{} = Graphs.load_revision(graph.revision_id)
  end
end
