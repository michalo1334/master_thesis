defmodule NetworkDefense.Evaluation.Study.StatusTest do
  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Evaluation.Study.Contracts.{Definition, StudyError}
  alias NetworkDefense.Evaluation.StudyConformance
  alias NetworkDefense.Evaluation.{StudyExecution, StudyFixtures, StudyPhase}
  alias NetworkDefense.Evaluations

  # Status cases:
  #   STUDY-STATUS-01  one execution row is returned without phase or history
  #   STUDY-STATUS-02  an invalid or absent execution ID is not found

  setup do
    definition = StudyConformance.parsed!()
    revision = StudyFixtures.insert_revision(%{definition: Definition.to_params(definition)})

    execution =
      StudyFixtures.insert_execution(revision, %{state: :awaiting_final})

    _pilot_phase = StudyFixtures.insert_phase(execution, :pilot_collection)
    _final_phase = StudyFixtures.insert_phase(execution, :final_collection)

    %{revision: revision, execution: execution}
  end

  test "STUDY-STATUS-01: WHEN a stored execution is requested, THE application SHALL return its StudyExecution without phase, evidence, collection-item, or Gust-task history",
       context do
    assert {:ok, %StudyExecution{} = execution} = Evaluations.study_status(context.execution.id)

    assert execution == Repo.get!(StudyExecution, context.execution.id)
    assert execution.state == :awaiting_final
    assert execution.study_revision_id == context.revision.id
  end

  test "STUDY-STATUS-02: WHEN the execution ID is invalid or absent, THE application SHALL return study_execution_not_found" do
    for execution_id <- ["invalid", Ecto.UUID.generate()] do
      assert Evaluations.study_status(execution_id) ==
               {:error, StudyError.study_execution_not_found()}
    end

    assert Repo.aggregate(StudyPhase, :count, :id) == 2
  end

  @tag type: :unit
  test "STUDY-STATUS-03: WHEN the execution read fails in the database, THE application SHALL return the bounded study storage error and SHALL propagate a programming defect" do
    :meck.new(Repo, [:passthrough, :no_link])
    on_exit(fn -> :meck.unload(Repo) end)

    for exception <- [
          %Postgrex.Error{message: "private database details"},
          %DBConnection.ConnectionError{message: "private connection details"}
        ] do
      :meck.expect(Repo, :get, fn _schema, _id -> raise exception end)

      assert Evaluations.study_status(Ecto.UUID.generate()) ==
               {:error, StudyError.study_execution_storage_failed()}
    end

    :meck.expect(Repo, :get, fn _schema, _id -> raise ArgumentError, "injected defect" end)

    assert_raise ArgumentError, "injected defect", fn ->
      Evaluations.study_status(Ecto.UUID.generate())
    end
  end
end
