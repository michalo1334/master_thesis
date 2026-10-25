defmodule NetworkDefense.Evaluation.Study.StudyPhasePersistenceTest do
  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase, StudyRevision}

  # One repository behavior:
  #
  # An execution holds at most one row for each fixed phase. A second row for
  # the same execution and phase is rejected.

  @phases [:pilot_collection, :pilot_analysis, :final_collection, :final_analysis]

  setup do
    revision =
      Repo.insert!(%StudyRevision{
        id: Ecto.UUID.generate(),
        study_id: "study-small",
        revision: 1,
        schema_version: 1,
        definition: %{"schema_version" => 1}
      })

    execution =
      Repo.insert!(
        StudyExecution.changeset(%StudyExecution{}, %{
          study_revision_id: revision.id,
          state: :collecting_pilot
        })
      )

    %{execution: execution}
  end

  test "STUDY-LIFE-REPO-01: a second row for one execution and phase is rejected", %{
    execution: execution
  } do
    for phase <- @phases do
      assert {:ok, %StudyPhase{phase: ^phase}} =
               Repo.insert(
                 StudyPhase.changeset(%StudyPhase{}, %{execution_id: execution.id, phase: phase})
               )
    end

    assert {:error, changeset} =
             Repo.insert(
               StudyPhase.changeset(%StudyPhase{}, %{
                 execution_id: execution.id,
                 phase: :pilot_collection
               })
             )

    assert errors_on(changeset) == %{execution_id: ["has already been taken"]}
    assert Repo.aggregate(StudyPhase, :count) == 4
  end
end
