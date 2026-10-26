defmodule NetworkDefense.Evaluation.Study.CancelTest do
  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Evaluation.Study.Contracts.{Definition, StudyError}
  alias NetworkDefense.Evaluation.Study.{Coordinator, Results}
  alias NetworkDefense.Evaluation.StudyConformance
  alias NetworkDefense.Evaluation.{StudyExecution, StudyFixtures, StudyResult}
  alias NetworkDefense.Evaluations

  # Cancel cases:
  #   STUDY-CANCEL-01  an active and a paused execution become cancelled
  #   STUDY-CANCEL-02  a repeated cancellation returns the same row
  #   STUDY-CANCEL-03  a succeeded or failed execution is rejected unchanged
  #   STUDY-CANCEL-04  late coordinator work cannot undo a cancellation

  @nonterminal_states [:collecting_pilot, :awaiting_final]
  @terminal_states [:succeeded, :failed]

  setup do
    %{revision: revision()}
  end

  test "STUDY-CANCEL-01: WHEN an active or paused execution is cancelled, THE application SHALL store cancelled and SHALL return the cancelled execution" do
    for state <- @nonterminal_states do
      execution = execution(state)

      assert {:ok, %StudyExecution{} = cancelled} = Evaluations.cancel_study(execution.id)
      assert cancelled.id == execution.id
      assert cancelled.state == :cancelled
      assert Repo.get!(StudyExecution, execution.id).state == :cancelled
    end
  end

  test "STUDY-CANCEL-02: WHEN an already-cancelled execution is cancelled again, THE application SHALL return the same cancelled execution" do
    execution = execution(:collecting_final)

    assert {:ok, %StudyExecution{state: :cancelled} = first} =
             Evaluations.cancel_study(execution.id)

    assert Evaluations.cancel_study(execution.id) == {:ok, first}
    assert Repo.get!(StudyExecution, execution.id).state == :cancelled
  end

  test "STUDY-CANCEL-03: WHEN a succeeded or failed execution is cancelled, THE application SHALL return study_execution_not_cancellable and SHALL not change the execution" do
    for state <- @terminal_states do
      execution = execution(state)

      assert Evaluations.cancel_study(execution.id) ==
               {:error, StudyError.study_execution_not_cancellable()}

      assert Repo.get!(StudyExecution, execution.id).state == state
    end
  end

  test "STUDY-CANCEL-04: WHEN late coordinator work completes after cancellation, THE application SHALL keep the execution cancelled and SHALL not create a compact result" do
    context = StudyFixtures.persist_final_conformance_lifecycle!(901)

    assert {:ok, %StudyExecution{state: :cancelled}} =
             Evaluations.cancel_study(context.execution.id)

    assert :ok = Coordinator.run(context.execution.id)

    assert Repo.get!(StudyExecution, context.execution.id).state == :cancelled
    assert Repo.aggregate(StudyResult, :count, :id) == 0

    assert Results.get_for_execution(context.execution.id) ==
             {:error, StudyError.result_unavailable()}
  end

  test "STUDY-CANCEL-05: WHEN the execution ID is invalid or absent, THE application SHALL return study_execution_not_found" do
    for execution_id <- ["invalid", Ecto.UUID.generate()] do
      assert Evaluations.cancel_study(execution_id) ==
               {:error, StudyError.study_execution_not_found()}
    end
  end

  defp revision do
    definition = StudyConformance.parsed!()
    StudyFixtures.insert_revision(%{definition: Definition.to_params(definition)})
  end

  defp execution(state) do
    revision = revision()

    execution =
      StudyFixtures.insert_execution(revision, %{
        state: state,
        error: terminal_error(state)
      })

    _phase = StudyFixtures.insert_phase(execution, :pilot_collection)
    execution
  end

  defp terminal_error(state) when state in @terminal_states,
    do: StudyError.to_params(StudyError.final_analysis_failed())

  defp terminal_error(_state), do: nil
end
