defmodule NetworkDefense.Evaluation.Study.StudyExecutionSelectionPersistenceTest do
  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Evaluation.{StudyExecution, StudyFixtures}

  setup do
    %{revision: StudyFixtures.insert_revision()}
  end

  test "FINAL-REPO-01: WHEN only part of the frozen Final selection is stored, THE execution SHALL reject the row",
       %{revision: revision} do
    partial_selections = [
      %{selected_candidate_id: "small"},
      %{selected_plan_count_per_side: 5},
      %{selected_attacks_per_plan: 10},
      %{pilot_override: false}
    ]

    for selection <- partial_selections do
      assert {:error, %Ecto.Changeset{}} =
               Repo.insert(
                 StudyExecution.changeset(
                   %StudyExecution{},
                   %{
                     study_revision_id: revision.id,
                     state: :awaiting_final
                   }
                   |> Map.merge(selection)
                 )
               )
    end

    assert Repo.aggregate(StudyExecution, :count) == 0
  end
end
