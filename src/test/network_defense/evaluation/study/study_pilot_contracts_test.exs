defmodule NetworkDefense.Evaluation.Study.StudyPilotContractsTest do
  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Evaluation.Pilot.Contracts.{PilotResult, Recommendation}
  alias NetworkDefense.Evaluation.Study.{PilotOutcome, PilotRequest}
  alias NetworkDefense.Evaluation.StudyConformance
  alias NetworkDefense.Evaluation.{StudyExecution, StudyFixtures}

  test "STUDY-PILOT-01: request mapping preserves declared comparison and candidate order" do
    definition = StudyConformance.parsed!()
    execution_id = Ecto.UUID.generate()
    revision_id = Ecto.UUID.generate()
    snapshot_id = Ecto.UUID.generate()

    execution = %StudyExecution{id: execution_id, study_revision_id: revision_id}

    assert {:ok, request} = PilotRequest.build(execution, definition, snapshot_id)

    assert request.pilot_id == execution_id
    assert request.study_revision_id == revision_id
    assert request.snapshot_id == snapshot_id
    assert request.family_id == definition.family.id

    assert Enum.map(request.expected_comparisons, &{&1.tier, &1.alternative, &1.reference}) ==
             Enum.map(definition.family.comparisons, fn comparison ->
               {comparison.tier, Atom.to_string(comparison.alternative),
                Atom.to_string(comparison.reference)}
             end)

    assert Enum.map(request.candidates, &{&1.id, &1.plan_count, &1.attacks_per_plan}) ==
             Enum.map(definition.pilot.candidates, fn candidate ->
               {candidate.id, candidate.plan_count_per_side, candidate.attacks_per_plan}
             end)
  end

  test "STUDY-PILOT-02: compact outcomes retain only data required by Final" do
    recommended = %PilotResult{
      outcome: "recommended",
      recommendation: %Recommendation{
        candidate_id: "declared-large",
        plan_count: 8,
        attacks_per_plan: 20
      }
    }

    assert {:ok, %PilotOutcome{} = outcome} = PilotOutcome.from_result(recommended)

    assert PilotOutcome.to_params(outcome) == %{
             "outcome" => "recommended",
             "candidate_id" => "declared-large",
             "plan_count_per_side" => 8,
             "attacks_per_plan" => 20
           }

    insufficient = %PilotResult{
      outcome: "insufficient",
      insufficient_reason: "no_passing_candidate"
    }

    assert {:ok, %PilotOutcome{} = outcome} = PilotOutcome.from_result(insufficient)

    assert PilotOutcome.to_params(outcome) == %{
             "outcome" => "insufficient",
             "reason" => "no_passing_candidate"
           }
  end

  test "STUDY-PILOT-03: nullable normalized outcomes preserve old execution rows" do
    revision = StudyFixtures.insert_revision()
    old_execution = StudyFixtures.insert_execution(revision)

    assert Repo.reload(old_execution).pilot_outcome == nil

    attrs = %{
      "outcome" => "recommended",
      "candidate_id" => "declared-large",
      "plan_count_per_side" => 8,
      "attacks_per_plan" => 20
    }

    assert {:ok, outcome} = PilotOutcome.parse(attrs)

    updated =
      old_execution
      |> StudyExecution.changeset(%{pilot_outcome: PilotOutcome.to_params(outcome)})
      |> Repo.update!()

    assert updated.pilot_outcome == attrs
    assert {:ok, ^outcome} = PilotOutcome.parse(updated.pilot_outcome)
  end
end
