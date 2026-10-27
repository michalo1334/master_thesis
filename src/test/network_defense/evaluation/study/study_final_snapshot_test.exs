defmodule NetworkDefense.Evaluation.Study.FinalSnapshotTest do
  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Evaluation.Study.{Cancel, FinalSnapshot, PilotSnapshot}
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError

  alias NetworkDefense.Evaluation.{
    EvidenceSnapshot,
    StudyCollectionItem,
    StudyExecution,
    StudyFixtures,
    StudyPhase
  }

  setup do
    collection = StudyFixtures.insert_collection_graph("study-final-snapshot", mission: true)
    definition = StudyFixtures.collection_definition(collection.graph, collection.foothold)
    study = StudyFixtures.study_with_two_phases(definition)

    pilot_items =
      StudyFixtures.collect_pilot_items(study.execution, study.pilot_phase, definition)

    {:ok, pilot_snapshot_id} =
      PilotSnapshot.assemble_and_store_pilot_snapshot(
        study.pilot_phase,
        pilot_items,
        definition
      )

    candidate = hd(definition.pilot.candidates)

    execution =
      study.execution
      |> StudyExecution.changeset(%{
        state: :collecting_final,
        selected_candidate_id: candidate.id,
        selected_plan_count_per_side: candidate.plan_count_per_side,
        selected_attacks_per_plan: candidate.attacks_per_plan,
        pilot_override: false
      })
      |> Repo.update!()

    final_items =
      StudyFixtures.collect_pilot_items(execution, study.final_phase, definition)

    Map.merge(study, %{
      definition: definition,
      execution: execution,
      pilot_items: pilot_items,
      final_items: final_items,
      pilot_snapshot_id: pilot_snapshot_id
    })
  end

  test "F19-02: WHEN Final collection runs, THE application SHALL create fresh Final phase items and runtime records",
       context do
    assert disjoint_ids?(context.pilot_items, context.final_items, & &1.id)
    assert disjoint_ids?(context.pilot_items, context.final_items, & &1.optimization_run_id)
    assert disjoint_ids?(context.pilot_items, context.final_items, & &1.experiment_id)

    assert {:ok, final_snapshot_id} =
             FinalSnapshot.assemble_and_store(
               context.final_phase,
               context.final_items,
               context.definition
             )

    assert final_snapshot_id != context.pilot_snapshot_id

    assert %EvidenceSnapshot{phase: :final, payload: payload} =
             Repo.get!(EvidenceSnapshot, final_snapshot_id)

    assert payload["evidence_role"] == "final"
    assert Repo.get!(StudyPhase, context.final_phase.id).snapshot_id == final_snapshot_id
  end

  test "F19-03: WHEN authoritative Final items are complete, THE application SHALL link one ordered snapshot and return it again",
       context do
    assert {:error, %StudyError{issues: [issue]}} =
             FinalSnapshot.assemble_and_store(
               context.final_phase,
               tl(context.final_items),
               context.definition
             )

    assert issue["code"] == "incomplete_final_evidence"

    assert {:ok, snapshot_id} =
             FinalSnapshot.assemble_and_store(
               context.final_phase,
               context.final_items,
               context.definition
             )

    assert {:ok, ^snapshot_id} =
             FinalSnapshot.assemble_and_store(
               context.final_phase,
               Enum.reverse(context.final_items),
               context.definition
             )

    comparisons = Repo.get!(EvidenceSnapshot, snapshot_id).payload["comparisons"]
    assert Enum.map(comparisons, & &1["position"]) == [0]
  end

  test "F19-03: WHEN a Final item reuses a Pilot runtime ID, THE application SHALL reject the snapshot",
       context do
    [pilot_item | _] = context.pilot_items
    [final_item | _] = context.final_items

    final_item =
      final_item
      |> StudyCollectionItem.link_changeset(%{
        optimization_run_id: pilot_item.optimization_run_id,
        experiment_id: pilot_item.experiment_id
      })
      |> Repo.update!()

    changed_items = [final_item | tl(context.final_items)]

    assert {:error, %StudyError{issues: [issue]}} =
             FinalSnapshot.assemble_and_store(
               context.final_phase,
               changed_items,
               context.definition
             )

    assert issue["code"] == "incomplete_final_evidence"
  end

  test "C-12: WHEN supplied snapshot items include any other replica position, THE Final snapshot boundary SHALL reject them",
       context do
    measured_items =
      StudyFixtures.collect_pilot_items(
        context.execution,
        context.final_phase,
        context.definition,
        1
      )

    assert {:ok, snapshot_id} =
             FinalSnapshot.assemble_and_store(
               context.final_phase,
               context.final_items,
               context.definition
             )

    assert {:error, %StudyError{issues: [issue]}} =
             FinalSnapshot.assemble_and_store(
               context.final_phase,
               measured_items,
               context.definition
             )

    assert issue["code"] == "incomplete_final_evidence"
    assert Repo.get!(StudyPhase, context.final_phase.id).snapshot_id == snapshot_id
  end

  test "C-12: WHEN supplied snapshot items belong to another phase, THE Final snapshot boundary SHALL reject them",
       context do
    assert {:error, %StudyError{issues: [issue]}} =
             FinalSnapshot.assemble_and_store(
               context.final_phase,
               context.pilot_items,
               context.definition
             )

    assert issue["code"] == "incomplete_final_evidence"
  end

  test "C-13: WHEN a cancellation commits before snapshot acceptance, THE boundary SHALL stop without stored evidence",
       context do
    assert {:stop, :cancelled} =
             FinalSnapshot.assemble_and_store(
               context.final_phase,
               context.final_items,
               context.definition,
               on_prepared: fn -> cancel!(context.execution.id) end
             )

    assert Repo.get!(StudyExecution, context.execution.id).state == :cancelled
    assert is_nil(Repo.get!(StudyPhase, context.final_phase.id).snapshot_id)
    assert final_snapshots() == []
  end

  test "C-13: WHEN a cancellation commits after snapshot acceptance, THE boundary SHALL keep the accepted snapshot",
       context do
    assert {:ok, snapshot_id} =
             FinalSnapshot.assemble_and_store(
               context.final_phase,
               context.final_items,
               context.definition
             )

    assert Repo.get_by!(EvidenceSnapshot, id: snapshot_id, phase: :final)

    assert {:ok, %StudyExecution{state: :cancelled}} = Cancel.cancel(context.execution.id)

    assert Repo.get!(StudyPhase, context.final_phase.id).snapshot_id == snapshot_id
    assert [_] = final_snapshots()
  end

  test "C-13: WHEN the execution is not collecting Final, THE boundary SHALL reject acceptance without a new row",
       context do
    context.execution
    |> StudyExecution.changeset(%{state: :collecting_pilot})
    |> Repo.update!()

    assert {:stop, :collecting_pilot} =
             FinalSnapshot.assemble_and_store(
               context.final_phase,
               context.final_items,
               context.definition
             )

    assert is_nil(Repo.get!(StudyPhase, context.final_phase.id).snapshot_id)
    assert final_snapshots() == []
  end

  defp cancel!(execution_id) do
    assert {:ok, %StudyExecution{state: :cancelled}} = Cancel.cancel(execution_id)
    :ok
  end

  defp final_snapshots do
    Repo.all(from snapshot in EvidenceSnapshot, where: snapshot.phase == :final)
  end

  defp disjoint_ids?(left, right, mapper) do
    left_ids = left |> Enum.map(mapper) |> MapSet.new()
    right_ids = right |> Enum.map(mapper) |> MapSet.new()
    MapSet.disjoint?(left_ids, right_ids)
  end
end
