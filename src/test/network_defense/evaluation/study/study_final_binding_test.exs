defmodule NetworkDefense.Evaluation.Study.FinalBindingTest do
  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Evaluation.{StudyExecution, StudyFixtures, StudyPhase}

  alias NetworkDefense.Evaluation.Family.Contracts.Identity
  alias NetworkDefense.Evaluation.Final.Binding
  alias NetworkDefense.Evaluation.Study.Contracts.Definition
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.{FinalSource, PilotOutcome}
  alias NetworkDefense.Evaluation.StudyConformance
  alias NetworkDefense.Repo

  setup do
    definition = StudyConformance.parsed!()
    revision = StudyFixtures.insert_revision(%{definition: Definition.to_params(definition)})
    candidate = hd(definition.pilot.candidates)

    outcome = %PilotOutcome{
      outcome: :recommended,
      candidate_id: candidate.id,
      plan_count_per_side: candidate.plan_count_per_side,
      attacks_per_plan: candidate.attacks_per_plan
    }

    execution =
      StudyFixtures.insert_execution(revision, %{
        state: :collecting_final,
        pilot_outcome: PilotOutcome.to_params(outcome),
        selected_candidate_id: candidate.id,
        selected_plan_count_per_side: candidate.plan_count_per_side,
        selected_attacks_per_plan: candidate.attacks_per_plan,
        pilot_override: false
      })

    pilot_phase = StudyFixtures.insert_phase(execution, :pilot_analysis)

    pilot_phase =
      Repo.update!(
        StudyPhase.changeset(pilot_phase, %{
          gust_run_id: 901,
          result_ref: PilotOutcome.to_params(outcome)
        })
      )

    source = %FinalSource{
      study_revision_id: revision.id,
      family_id: definition.family.id,
      candidate_id: candidate.id,
      plan_count_per_side: candidate.plan_count_per_side,
      attacks_per_plan: candidate.attacks_per_plan,
      pilot_analysis_phase_id: pilot_phase.id,
      expected_comparisons: expected_comparisons(definition)
    }

    %{definition: definition, execution: execution, pilot_phase: pilot_phase, source: source}
  end

  test "FINAL-BIND-02: WHEN Final input matches the frozen source, THE shared binding SHALL return the accepted Pilot analysis phase",
       context do
    assert {:ok, phase} = Binding.verify(context.execution.id, context.source)
    assert phase.id == context.pilot_phase.id
    assert phase.phase == :pilot_analysis
    assert is_integer(phase.gust_run_id)
  end

  test "FINAL-BIND-03: WHEN an execution is in an active Final state or succeeded, THE shared binding SHALL accept its frozen source",
       context do
    for state <- [:collecting_final, :analyzing_final, :succeeded] do
      context.execution
      |> StudyExecution.changeset(%{state: state})
      |> Repo.update!()

      assert {:ok, %StudyPhase{id: phase_id}} =
               Binding.verify(context.execution.id, context.source)

      assert phase_id == context.pilot_phase.id
    end
  end

  test "FINAL-BIND-04: WHEN an execution is not in a usable Final state, THE shared binding SHALL return one bounded conflict",
       context do
    expected_error = StudyError.final_binding_not_allowed()

    for state <- [:collecting_pilot, :analyzing_pilot, :awaiting_final, :cancelled, :failed] do
      context.execution
      |> StudyExecution.changeset(%{state: state})
      |> Repo.update!()

      assert {:error, ^expected_error} = Binding.verify(context.execution.id, context.source)
    end
  end

  test "FINAL-BIND-01: WHEN Final input differs from one frozen source identity, THE shared binding SHALL return a bounded mismatch error",
       context do
    mismatches = [
      {:candidate_id, %{context.source | candidate_id: "medium"}},
      {:plan_count_per_side,
       %{context.source | plan_count_per_side: context.source.plan_count_per_side + 1}},
      {:attacks_per_plan,
       %{context.source | attacks_per_plan: context.source.attacks_per_plan + 1}},
      {:family_id, %{context.source | family_id: "different-family"}},
      {:ordered_comparisons,
       %{context.source | expected_comparisons: Enum.reverse(context.source.expected_comparisons)}},
      {:study_revision_id, %{context.source | study_revision_id: Ecto.UUID.generate()}},
      {:pilot_analysis_phase_id,
       %{context.source | pilot_analysis_phase_id: Ecto.UUID.generate()}}
    ]

    for {field, mismatch} <- mismatches do
      assert {:error, %StudyError{}} =
               Binding.verify(context.execution.id, mismatch),
             Atom.to_string(field)
    end
  end

  defp expected_comparisons(%Definition{} = definition) do
    Enum.map(definition.family.comparisons, fn comparison ->
      %Identity{
        tier: comparison.tier,
        budget: comparison.budget,
        alternative: Atom.to_string(comparison.alternative),
        reference: Atom.to_string(comparison.reference),
        outcome: comparison.outcome
      }
    end)
  end
end
