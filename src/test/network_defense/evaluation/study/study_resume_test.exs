defmodule NetworkDefense.Evaluation.Study.ResumeTest do
  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Evaluation.{StudyExecution, StudyFixtures, StudyPhase}

  alias NetworkDefense.Evaluation.Study.Contracts.Definition
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.{PilotOutcome, Resume}
  alias NetworkDefense.Evaluation.StudyConformance
  alias NetworkDefense.Repo

  defmodule CoordinatorStub do
    def start(_execution_id), do: {:ok, self()}
  end

  defmodule FailingCoordinatorStub do
    def start(_execution_id), do: {:error, StudyError.coordinator_not_startable()}
  end

  defmodule RaisingCoordinatorStub do
    def start(_execution_id), do: raise(ArgumentError, "injected coordinator defect")
  end

  test "FINAL-RESUME-07: WHEN coordinator startup raises a programming exception, resume SHALL propagate it after committing the selection" do
    context = paused_context(:recommended)

    assert_raise ArgumentError, "injected coordinator defect", fn ->
      Resume.resume(context.execution.id, :recommended, coordinator: RaisingCoordinatorStub)
    end

    assert Repo.get!(StudyExecution, context.execution.id).state == :collecting_final
  end

  test "FINAL-RESUME-08: WHEN the execution ID is invalid or absent, resume SHALL keep its not-found error" do
    for id <- ["invalid", Ecto.UUID.generate()] do
      assert resume(id, :recommended) == {:error, StudyError.study_execution_not_found()}
    end
  end

  test "FINAL-RESUME-01: WHEN a valid recommendation resumes, THE application SHALL freeze its candidate and counts, set override false, enter collecting_final, and create one empty Final phase" do
    context = paused_context(:recommended)

    assert {:ok, resumed} = resume(context.execution.id, :recommended)

    assert resumed.id == context.execution.id
    assert resumed.state == :collecting_final
    assert resumed.selected_candidate_id == context.candidate.id
    assert resumed.selected_plan_count_per_side == context.candidate.plan_count_per_side
    assert resumed.selected_attacks_per_plan == context.candidate.attacks_per_plan
    assert resumed.pilot_override == false

    assert %StudyPhase{
             execution_id: execution_id,
             phase: :final_collection,
             gust_run_id: nil,
             snapshot_id: nil,
             result_ref: nil,
             error: nil
           } =
             Repo.get_by!(StudyPhase,
               execution_id: context.execution.id,
               phase: :final_collection
             )

    assert execution_id == context.execution.id
    assert Repo.aggregate(StudyPhase, :count, :id) == 2
  end

  test "FINAL-RESUME-02: WHEN an insufficient Pilot resumes with a declared override, THE application SHALL freeze its candidate and counts, preserve insufficiency, set override true, and enter collecting_final" do
    context = paused_context(:insufficient)
    existing_phase = StudyFixtures.insert_phase(context.execution, :final_collection)

    assert {:ok, resumed} =
             resume(context.execution.id, {:override_insufficient, context.candidate.id})

    assert resumed.state == :collecting_final
    assert resumed.selected_candidate_id == context.candidate.id
    assert resumed.selected_plan_count_per_side == context.candidate.plan_count_per_side
    assert resumed.selected_attacks_per_plan == context.candidate.attacks_per_plan
    assert resumed.pilot_override == true
    assert resumed.pilot_outcome == context.execution.pilot_outcome

    assert %StudyPhase{
             id: phase_id,
             gust_run_id: nil,
             snapshot_id: nil,
             result_ref: nil,
             error: nil
           } =
             Repo.get_by!(StudyPhase,
               execution_id: context.execution.id,
               phase: :final_collection
             )

    assert phase_id == existing_phase.id
    assert Repo.aggregate(StudyPhase, :count, :id) == 2
  end

  test "FINAL-RESUME-03: WHEN resume uses a wrong tagged form or undeclared candidate, THE application SHALL return a bounded error and leave the paused execution and phases unchanged" do
    invalid_selections = [
      {:recommended_with_insufficient_form, :recommended, {:override_insufficient, "medium"}},
      {:insufficient_with_recommended_form, :insufficient, :recommended},
      {:insufficient_with_undeclared_candidate, :insufficient,
       {:override_insufficient, "not-declared"}}
    ]

    for {_case, outcome, selection} <- invalid_selections do
      context = paused_context(outcome)

      assert {:error, %StudyError{}} = resume(context.execution.id, selection)

      assert %StudyExecution{
               state: :awaiting_final,
               selected_candidate_id: nil,
               selected_plan_count_per_side: nil,
               selected_attacks_per_plan: nil,
               pilot_override: nil
             } = Repo.reload!(context.execution)

      assert Repo.get_by(StudyPhase,
               execution_id: context.execution.id,
               phase: :final_collection
             ) == nil
    end
  end

  test "FINAL-RESUME-04: WHEN the accepted Pilot source is incomplete, THE application SHALL reject resume without changing the paused execution" do
    context = paused_context(:recommended, pilot_result_ref: nil)

    assert {:error, %StudyError{}} = resume(context.execution.id, :recommended)

    assert %StudyExecution{
             state: :awaiting_final,
             selected_candidate_id: nil,
             selected_plan_count_per_side: nil,
             selected_attacks_per_plan: nil,
             pilot_override: nil
           } = Repo.reload!(context.execution)

    assert Repo.get_by(StudyPhase, execution_id: context.execution.id, phase: :final_collection) ==
             nil
  end

  test "FINAL-RESUME-05: WHEN a non-empty Final phase conflicts with resume, THE application SHALL roll back the frozen selection" do
    context = paused_context(:recommended)
    final_phase = StudyFixtures.insert_phase(context.execution, :final_collection)

    final_phase =
      Repo.update!(StudyPhase.changeset(final_phase, %{gust_run_id: 902}))

    assert {:error, %StudyError{} = error} = resume(context.execution.id, :recommended)
    assert error == StudyError.final_phase_conflict()

    assert %StudyExecution{
             state: :awaiting_final,
             selected_candidate_id: nil,
             selected_plan_count_per_side: nil,
             selected_attacks_per_plan: nil,
             pilot_override: nil
           } = Repo.reload!(context.execution)

    assert %StudyPhase{
             id: phase_id,
             gust_run_id: 902,
             snapshot_id: nil,
             result_ref: nil,
             error: nil
           } = Repo.reload!(final_phase)

    assert phase_id == final_phase.id
  end

  test "FINAL-RESUME-06: WHEN Final coordinator startup fails after commit, THE application SHALL return a bounded error and keep collecting_final" do
    context = paused_context(:recommended)

    assert {:error, %StudyError{code: "conflict"}} =
             Resume.resume(context.execution.id, :recommended,
               coordinator: FailingCoordinatorStub
             )

    assert Repo.get!(StudyExecution, context.execution.id).state == :collecting_final

    assert Repo.get_by!(StudyPhase,
             execution_id: context.execution.id,
             phase: :final_collection
           )
  end

  defp resume(execution_id, selection) do
    Resume.resume(execution_id, selection, coordinator: CoordinatorStub)
  end

  defp paused_context(outcome_kind, opts \\ []) do
    definition = StudyConformance.parsed!()
    revision = StudyFixtures.insert_revision(%{definition: Definition.to_params(definition)})
    candidate = hd(definition.pilot.candidates)
    outcome = outcome(outcome_kind, candidate)

    execution =
      StudyFixtures.insert_execution(revision, %{
        state: :awaiting_final,
        pilot_outcome: PilotOutcome.to_params(outcome)
      })

    pilot_phase = StudyFixtures.insert_phase(execution, :pilot_analysis)

    Repo.update!(
      StudyPhase.changeset(pilot_phase, %{
        gust_run_id: 901,
        result_ref: Keyword.get(opts, :pilot_result_ref, PilotOutcome.to_params(outcome))
      })
    )

    %{revision: revision, definition: definition, execution: execution, candidate: candidate}
  end

  defp outcome(:recommended, candidate) do
    %PilotOutcome{
      outcome: :recommended,
      candidate_id: candidate.id,
      plan_count_per_side: candidate.plan_count_per_side,
      attacks_per_plan: candidate.attacks_per_plan
    }
  end

  defp outcome(:insufficient, _candidate) do
    %PilotOutcome{outcome: :insufficient, reason: "no_passing_candidate"}
  end
end
