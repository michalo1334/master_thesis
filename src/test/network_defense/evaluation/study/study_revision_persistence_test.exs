defmodule NetworkDefense.Evaluation.Study.StudyRevisionPersistenceTest do
  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.StudyConformance
  alias NetworkDefense.Evaluation.StudyRevision
  alias NetworkDefense.Evaluations
  alias NetworkDefense.Graph.{Graph, GraphRevision}
  alias NetworkDefense.Repo

  # Two observable revision-creation behaviors:
  #
  # 1. valid YAML whose graph revisions exist stores one normalized revision;
  # 2. one declared graph revision that does not exist stores nothing and
  #    returns a bounded error.

  setup do
    declared =
      StudyConformance.definition()["graphs"]
      |> Enum.map(& &1["graph_revision_id"])

    %{declared: declared}
  end

  test "REVISION-01: valid YAML with existing graph revisions stores one revision", %{
    declared: declared
  } do
    Enum.each(declared, &insert_graph_revision/1)

    assert {:ok, %StudyRevision{} = revision} =
             Evaluations.create_study_revision(StudyConformance.yaml())

    assert revision.study_id == "study-small"
    assert revision.revision == 1
    assert revision.schema_version == 1
    assert revision.definition == StudyConformance.definition()
    assert %DateTime{} = revision.inserted_at

    assert Repo.aggregate(StudyRevision, :count) == 1
    assert Repo.get!(StudyRevision, revision.id).definition == StudyConformance.definition()
  end

  test "REVISION-02: an unknown graph revision stores nothing", %{declared: [known, missing]} do
    insert_graph_revision(known)

    assert {:error, %StudyError{code: "validation_failed", issues: [issue]}} =
             Evaluations.create_study_revision(StudyConformance.yaml())

    assert issue["code"] == "graph_revision_not_found"
    assert issue["path"] == ["graphs", 1, "graph_revision_id"]
    refute inspect(issue) =~ missing

    assert Repo.aggregate(StudyRevision, :count) == 0
  end

  defp insert_graph_revision(revision_id) do
    {:ok, graph} = Repo.insert(%Graph{id: Ecto.UUID.generate()})

    Repo.insert!(%GraphRevision{
      id: revision_id,
      graph_id: graph.id,
      number: 1,
      kind: :initial,
      title: "fixture"
    })
  end
end
