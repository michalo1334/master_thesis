defmodule NetworkDefense.Evaluation.Study.StudyCollectionItemPersistenceTest do
  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Evaluation.Study.CollectionItems
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.{StudyCollectionItem, StudyFixtures}
  alias NetworkDefense.Repo

  # Three repository behaviors of one positional identity:
  #
  # 1. a repeated request returns the stored item and stores nothing new;
  # 2. the same positions in another phase return another item;
  # 3. an identity that the database cannot store, or a position and phase the
  #    repository rejects, return a bounded error and store nothing.
  #
  # The unique identity is the phase, the replica position, and the item
  # position. Scientific identity stays in the declared work and never enters
  # the row.

  setup do
    StudyFixtures.study_with_two_phases()
  end

  test "COLLECTION-REPO-01: a repeated positional request returns the stored item", %{
    pilot_phase: phase
  } do
    assert {:ok, %StudyCollectionItem{} = item} = CollectionItems.get_or_create(phase.id, 0, 0)

    assert item.study_phase_id == phase.id
    assert item.replica_position == 0
    assert item.item_position == 0
    assert item.optimization_run_id == nil
    assert item.experiment_id == nil
    assert %DateTime{} = item.inserted_at

    assert {:ok, %StudyCollectionItem{} = repeated} =
             CollectionItems.get_or_create(phase.id, 0, 0)

    assert repeated.id == item.id
    assert repeated.inserted_at == item.inserted_at
    assert Repo.aggregate(StudyCollectionItem, :count) == 1
  end

  test "COLLECTION-REPO-02: the same positions in another phase return another item", %{
    pilot_phase: pilot_phase,
    final_phase: final_phase
  } do
    assert {:ok, %StudyCollectionItem{} = pilot_item} =
             CollectionItems.get_or_create(pilot_phase.id, 1, 2)

    assert {:ok, %StudyCollectionItem{} = final_item} =
             CollectionItems.get_or_create(final_phase.id, 1, 2)

    refute final_item.id == pilot_item.id
    assert final_item.study_phase_id == final_phase.id
    assert final_item.replica_position == 1
    assert final_item.item_position == 2
    assert Repo.aggregate(StudyCollectionItem, :count) == 2
  end

  test "COLLECTION-REPO-03: a phase that does not exist stores nothing and returns a bounded error",
       %{pilot_phase: phase} do
    assert {:error, %StudyError{code: "unavailable", issues: [issue]}} =
             CollectionItems.get_or_create(Ecto.UUID.generate(), 0, 0)

    assert issue["code"] == "storage_failed"
    assert issue["path"] == []
    assert Repo.aggregate(StudyCollectionItem, :count) == 0

    assert {:ok, %StudyCollectionItem{study_phase_id: stored_phase_id}} =
             CollectionItems.get_or_create(phase.id, 0, 0)

    assert stored_phase_id == phase.id
  end

  test "COLLECTION-REPO-04: an identity that is not a stored position or phase returns a bounded error",
       %{pilot_phase: phase} do
    assert {:error, %StudyError{code: "validation_failed", issues: [position_issue]}} =
             CollectionItems.get_or_create(phase.id, 0, -1)

    assert position_issue["code"] == "invalid_collection_position"
    assert position_issue["path"] == ["item_position"]

    assert {:error, %StudyError{code: "validation_failed", issues: [phase_issue]}} =
             CollectionItems.get_or_create("not-a-phase", 0, 0)

    assert phase_issue["code"] == "invalid_study_phase"
    assert Repo.aggregate(StudyCollectionItem, :count) == 0
  end
end
