defmodule NetworkDefense.Evaluation.Study.FinalRequestTest do
  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Evaluation.EvidenceSnapshots
  alias NetworkDefense.Evaluation.Final.Binding
  alias NetworkDefense.Evaluation.Final.Contracts.{FinalError, Request, SnapshotInput}

  alias NetworkDefense.Evaluation.Study.{
    FinalBindingContext,
    FinalRequest,
    FinalSnapshot,
    PilotOutcome
  }

  alias NetworkDefense.Evaluation.{
    StudyExecution,
    StudyFixtures,
    StudyPhase,
    StudyPhaseRun
  }

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError

  setup do
    final_context(:recommended)
  end

  test "F20-01: WHEN Final analysis starts, THE application SHALL validate the frozen lifecycle source before it creates a Gust run",
       context do
    assert {:ok, %Request{} = request} =
             FinalRequest.build(context.execution.id, context.snapshot_id)

    params = Request.to_params(request)
    assert params["study_execution_id"] == context.execution.id
    refute Map.has_key?(params, "candidate_id")
    refute Map.has_key?(params, "pilot_override")
    refute Map.has_key?(params, "pilot_analysis_phase_id")
    assert params["source_pilot_run_id"] == context.pilot_phase.gust_run_id
    assert {:ok, _payload} = Binding.verify(request)

    mismatches = [
      {:execution, %{request | study_execution_id: Ecto.UUID.generate()}},
      {:counts, %{request | plan_count: request.plan_count + 1}},
      {:pilot_run, %{request | source_pilot_run_id: request.source_pilot_run_id + 1}},
      {:family, %{request | family_id: "changed-family"}},
      {:revision, %{request | study_revision_id: Ecto.UUID.generate()}},
      {:comparison_order, %{request | expected_comparisons: []}}
    ]

    for {field, mismatch} <- mismatches do
      assert {:error, %FinalError{}} = Binding.verify(mismatch), Atom.to_string(field)
    end

    context.execution
    |> StudyExecution.changeset(%{selected_candidate_id: "not-declared"})
    |> Repo.update!()

    assert {:error, %FinalError{}} = Binding.verify(request)

    context.execution
    |> Repo.reload!()
    |> StudyExecution.changeset(%{selected_candidate_id: context.execution.selected_candidate_id})
    |> Repo.update!()

    Repo.delete!(context.pilot_phase)
    assert {:error, %FinalError{}} = Binding.verify(request)
  end

  test "F20-01: WHEN a request names a different valid Final snapshot, THE binding SHALL reject it",
       context do
    assert {:ok, %Request{} = request} =
             FinalRequest.build(context.execution.id, context.snapshot_id)

    assert {:ok, stored, payload} = EvidenceSnapshots.load_final(context.snapshot_id)

    duplicate_input = %SnapshotInput{
      schema_version: stored.schema_version,
      study_revision_id: stored.study_revision_id,
      phase: :final,
      family_id: stored.family_id,
      payload: payload
    }

    assert {:ok, other_snapshot} = EvidenceSnapshots.create_final(duplicate_input)
    assert other_snapshot.id != context.snapshot_id

    assert {:error,
            %FinalError{
              code: "validation_failed",
              issues: [%{"code" => "changed_pilot_source"}]
            }} = Binding.verify(%{request | snapshot_id: other_snapshot.id})
  end

  test "F20-02: WHEN an insufficient Pilot has an approved frozen override, THE Final analysis SHALL accept the source and keep the Pilot outcome insufficient" do
    context = final_context(:insufficient)

    assert {:ok, %Request{} = request} =
             FinalRequest.build(context.execution.id, context.snapshot_id)

    assert {:ok, _payload} = Binding.verify(request)

    execution = Repo.get!(StudyExecution, context.execution.id)
    assert execution.pilot_override == true

    assert {:ok, %PilotOutcome{outcome: :insufficient}} =
             PilotOutcome.parse(execution.pilot_outcome)
  end

  test "F20-02: WHEN the Final tier-run family is incomplete or misordered, THE Final analysis source SHALL be rejected",
       context do
    assert {:ok, %Request{}} =
             FinalRequest.build(context.execution.id, context.snapshot_id)

    # One extra tier row no longer matches the declared tier order.
    %StudyPhaseRun{}
    |> StudyPhaseRun.changeset(%{
      study_phase_id: context.final_phase.id,
      tier: "extra",
      tier_position: 9,
      gust_run_id: 999_001
    })
    |> Repo.insert!()

    assert {:error, %FinalError{}} =
             FinalRequest.build(context.execution.id, context.snapshot_id)

    assert {:error, %StudyError{}} =
             FinalBindingContext.load_for_analysis(context.execution.id)

    # No tier row left: the family is incomplete.
    Repo.delete_all(
      from run in StudyPhaseRun, where: run.study_phase_id == ^context.final_phase.id
    )

    assert {:error, %FinalError{}} =
             FinalRequest.build(context.execution.id, context.snapshot_id)

    assert {:error, %StudyError{}} =
             FinalBindingContext.load_for_analysis(context.execution.id)
  end

  defp final_context(outcome_kind) do
    collection =
      StudyFixtures.insert_collection_graph(
        "study-final-request-#{outcome_kind}-#{System.unique_integer([:positive])}",
        mission: true
      )

    definition = StudyFixtures.collection_definition(collection.graph, collection.foothold)
    study = StudyFixtures.study_with_two_phases(definition)
    candidate = hd(definition.pilot.candidates)
    outcome = outcome(outcome_kind, candidate)

    pilot_phase = StudyFixtures.insert_phase(study.execution, :pilot_analysis)

    pilot_phase =
      pilot_phase
      |> StudyPhase.changeset(%{
        gust_run_id: 901,
        result_ref: PilotOutcome.to_params(outcome)
      })
      |> Repo.update!()

    execution =
      study.execution
      |> StudyExecution.changeset(%{
        state: :collecting_final,
        pilot_outcome: PilotOutcome.to_params(outcome),
        selected_candidate_id: candidate.id,
        selected_plan_count_per_side: candidate.plan_count_per_side,
        selected_attacks_per_plan: candidate.attacks_per_plan,
        pilot_override: outcome_kind == :insufficient
      })
      |> Repo.update!()

    final_phase = study.final_phase
    _phase_runs = StudyFixtures.link_final_phase_runs!(definition, final_phase)

    items = StudyFixtures.collect_pilot_items(execution, final_phase, definition)
    {:ok, snapshot_id} = FinalSnapshot.assemble_and_store(final_phase, items, definition)

    execution =
      execution
      |> Repo.reload!()
      |> StudyExecution.changeset(%{state: :analyzing_final})
      |> Repo.update!()

    _analysis_phase = StudyFixtures.insert_phase(execution, :final_analysis)

    %{
      definition: definition,
      execution: execution,
      final_phase: Repo.reload!(final_phase),
      pilot_phase: pilot_phase,
      snapshot_id: snapshot_id
    }
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
