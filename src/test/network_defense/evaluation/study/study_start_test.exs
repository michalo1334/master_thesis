defmodule NetworkDefense.Evaluation.Study.StartTest do
  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Evaluation.Study.Contracts.{Definition, StudyError}
  alias NetworkDefense.Evaluation.Study.{Lifecycle, Start}
  alias NetworkDefense.Evaluation.StudyConformance
  alias NetworkDefense.Evaluation.{StudyExecution, StudyFixtures, StudyPhase}
  alias NetworkDefense.Evaluations

  # Start cases:
  #   STUDY-START-01  one execution and one Pilot collection phase, committed
  #                   before the coordinator starts
  #   STUDY-START-02  an invalid or absent revision creates no row
  #   STUDY-START-03  a coordinator-start failure keeps the committed rows

  defmodule RecordingCoordinator do
    alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase}
    alias NetworkDefense.Repo

    def start(execution_id) do
      execution = Repo.get(StudyExecution, execution_id)

      phase =
        Repo.get_by(StudyPhase, execution_id: execution_id, phase: :pilot_collection)

      send(self(), {:coordinator_started, execution, phase})
      {:ok, self()}
    end
  end

  defmodule FailingCoordinator do
    def start(_execution_id), do: {:error, StudyError.coordinator_not_startable()}
  end

  setup do
    definition = StudyConformance.parsed!()

    revision =
      StudyFixtures.insert_revision(%{definition: Definition.to_params(definition)})

    %{revision: revision, definition: definition}
  end

  test "STUDY-START-01: WHEN a stored study revision starts, THE application SHALL create one collecting_pilot execution and one pilot_collection phase in one transaction before it starts the coordinator",
       context do
    assert {:ok, %StudyExecution{} = execution} =
             Start.start(context.revision.id, coordinator: RecordingCoordinator)

    assert execution.study_revision_id == context.revision.id
    assert execution.state == Lifecycle.initial_state()
    assert execution.pilot_outcome == nil
    assert execution.selected_candidate_id == nil
    assert execution.error == nil

    assert Repo.aggregate(StudyExecution, :count, :id) == 1
    assert Repo.aggregate(StudyPhase, :count, :id) == 1

    assert %StudyPhase{
             execution_id: execution_id,
             phase: :pilot_collection,
             gust_run_id: nil,
             snapshot_id: nil,
             result_ref: nil,
             error: nil
           } = Repo.get_by!(StudyPhase, execution_id: execution.id, phase: :pilot_collection)

    assert execution_id == execution.id

    assert_receive {:coordinator_started, %StudyExecution{id: started_id}, %StudyPhase{} = phase}
    assert started_id == execution.id
    assert phase.phase == :pilot_collection
  end

  test "STUDY-START-02: WHEN the revision ID is invalid or absent, THE application SHALL return study_revision_not_found and SHALL create no execution or phase" do
    for revision_id <- ["invalid", Ecto.UUID.generate()] do
      assert Start.start(revision_id, coordinator: RecordingCoordinator) ==
               {:error, StudyError.study_revision_not_found()}
    end

    assert Evaluations.start_study(Ecto.UUID.generate()) ==
             {:error, StudyError.study_revision_not_found()}

    assert Repo.aggregate(StudyExecution, :count, :id) == 0
    assert Repo.aggregate(StudyPhase, :count, :id) == 0
    refute_received {:coordinator_started, _execution, _phase}
  end

  test "STUDY-START-03: WHEN coordinator startup fails after commit, THE application SHALL return a bounded error and SHALL keep the committed execution and phase",
       context do
    assert {:error, %StudyError{code: "conflict"}} =
             Start.start(context.revision.id, coordinator: FailingCoordinator)

    assert %StudyExecution{state: :collecting_pilot} = execution = Repo.one(StudyExecution)

    assert %StudyPhase{phase: :pilot_collection, gust_run_id: nil} =
             Repo.get_by!(StudyPhase, execution_id: execution.id, phase: :pilot_collection)
  end
end
