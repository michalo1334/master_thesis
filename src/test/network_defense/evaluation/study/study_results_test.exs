defmodule NetworkDefense.Evaluation.Study.ResultsTest do
  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Evaluation.Study.{CompactResult, FinalRequest, Results}
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError

  alias NetworkDefense.Evaluation.{
    FinalConformance,
    PilotConformance,
    StudyExecution,
    StudyFixtures,
    StudyPhase,
    StudyResult
  }

  alias NetworkDefense.Evaluations

  setup do
    fixture = StudyFixtures.final_conformance_fixture()
    context = StudyFixtures.persist_final_conformance_lifecycle!(901)

    {:ok, pilot_snapshot} =
      PilotConformance.store_snapshot(PilotConformance.snapshot())

    {:ok, final_snapshot} =
      FinalConformance.store_snapshot(fixture.snapshot)

    context = StudyFixtures.accept_final_collection!(context, final_snapshot.id, 902)

    pilot_collection = StudyFixtures.insert_phase(context.execution, :pilot_collection)

    pilot_collection =
      pilot_collection
      |> StudyPhase.changeset(%{gust_run_id: 801, snapshot_id: pilot_snapshot.id})
      |> Repo.update!()

    final_collection = context.final_phase
    final_analysis = StudyFixtures.insert_phase(context.execution, :final_analysis)

    final_analysis =
      final_analysis
      |> StudyPhase.changeset(%{gust_run_id: 903})
      |> Repo.update!()

    {:ok, request} = FinalRequest.build(context.execution.id, final_snapshot.id)

    Map.merge(context, %{
      final_analysis: final_analysis,
      final_collection: final_collection,
      final_result: FinalConformance.result!(request, fixture),
      pilot_collection: pilot_collection,
      request: request
    })
  end

  test "F21-01: WHEN Final analysis returns one valid complete family, THE application SHALL store one immutable compact result and succeed atomically",
       context do
    assert {:ok, %CompactResult{} = compact} =
             Results.create_success(context.execution, context.final_result)

    assert Repo.get!(StudyExecution, context.execution.id).state == :succeeded
    assert Repo.aggregate(StudyResult, :count, :id) == 1

    row = Repo.get_by!(StudyResult, execution_id: context.execution.id)
    assert row.schema_version == 1
    refute Map.has_key?(row, :updated_at)
    assert compact.execution_id == context.execution.id
    assert compact.study_revision_id == context.revision.id
    assert compact.selection.candidate_id == context.candidate.id
    assert compact.selection.pilot_override == false
    assert compact.pilot_collection.phase_id == context.pilot_collection.id
    assert compact.pilot_analysis.phase_id == context.pilot_phase.id
    assert compact.final_collection.phase_id == context.final_collection.id
    assert compact.final_analysis.phase_id == context.final_analysis.id
    assert compact.final_result.family_id == context.definition.family.id

    assert compact.revision_assertions ==
             context.definition.study.revisions

    assert compact.timing == nil

    encoded = Jason.encode!(row.data)
    refute encoded =~ "mission_impacts"
    refute encoded =~ "attack_seeds"
    refute encoded =~ "collection_items"
    refute encoded =~ "task_history"

    assert Repo.reload!(context.final_analysis).result_ref == %{
             "study_result_id" => row.id
           }

    assert_raise Postgrex.Error, fn ->
      Repo.transaction(fn ->
        row |> Ecto.Changeset.change(data: %{}) |> Repo.update!()
      end)
    end

    assert_raise Postgrex.Error, fn ->
      Repo.transaction(fn -> Repo.delete!(row) end)
    end
  end

  test "F21-04: WHEN a result exists for a succeeded execution, THE application SHALL return the typed compact result; otherwise it SHALL return result_unavailable",
       context do
    assert {:error, %StudyError{} = unavailable} =
             Results.get_for_execution(context.execution.id)

    assert unavailable == StudyError.result_unavailable()

    assert {:ok, created} = Results.create_success(context.execution, context.final_result)
    assert {:ok, loaded} = Results.get_for_execution(context.execution.id)
    assert loaded == created
  end

  test "F21-05: WHEN a Final rejection decision contradicts its adjusted p-value, THE application SHALL reject success without a row or state change",
       context do
    [first | rest] = context.final_result.comparisons

    changed = %{
      first
      | adjustment: %{first.adjustment | reject_null: not first.adjustment.reject_null}
    }

    invalid = %{context.final_result | comparisons: [changed | rest]}

    assert {:error, error} = Results.create_success(context.execution, invalid)
    assert error == StudyError.final_result_invalid()
    assert Repo.aggregate(StudyResult, :count, :id) == 0
    assert Repo.reload!(context.execution).state == :analyzing_final
    assert Repo.reload!(context.final_analysis).result_ref == nil
  end

  test "F21-06: WHEN a compact payload contains a contradictory rejection decision, THE parser SHALL reject it",
       context do
    assert {:ok, compact} = Results.create_success(context.execution, context.final_result)
    params = CompactResult.to_params(compact)

    invalid =
      update_in(
        params,
        ["final_result", "comparisons", Access.at(0), "adjustment", "reject_null"],
        &(!&1)
      )

    assert {:error, error} = CompactResult.parse(invalid)
    assert error == StudyError.final_result_invalid()
  end

  test "F21-07: WHEN a compact payload contains an unknown field or an invalid reference, THE parser SHALL reject it",
       context do
    assert {:ok, compact} = Results.create_success(context.execution, context.final_result)
    params = CompactResult.to_params(compact)

    invalid_payloads = [
      Map.put(params, "extra", true),
      put_in(params, ["final_collection", "extra"], true),
      put_in(params, ["revision_assertions", "extra"], "revision"),
      put_in(params, ["final_analysis", "gust_run_id"], 0),
      Map.put(params, "timing", "")
    ]

    for invalid <- invalid_payloads do
      assert {:error, error} = CompactResult.parse(invalid)
      assert error == StudyError.final_result_invalid()
    end
  end

  test "STUDY-RESULT-01: WHEN a public result read happens before success, THE application SHALL return result_unavailable, and after success it SHALL return the typed compact result",
       context do
    assert Evaluations.study_result(context.execution.id) ==
             {:error, StudyError.result_unavailable()}

    assert {:ok, created} = Results.create_success(context.execution, context.final_result)

    assert {:ok, %CompactResult{} = loaded} = Evaluations.study_result(context.execution.id)
    assert loaded == created
  end

  test "F21-08: WHEN result insertion violates uniqueness, THE application SHALL return a bounded storage error and keep the transaction unchanged",
       context do
    %StudyResult{}
    |> StudyResult.create_changeset(%{
      execution_id: context.execution.id,
      schema_version: 1,
      data: %{}
    })
    |> Repo.insert!()

    assert {:error, error} = Results.create_success(context.execution, context.final_result)
    assert error == StudyError.final_result_storage_failed()
    assert Repo.aggregate(StudyResult, :count, :id) == 1
    assert Repo.reload!(context.execution).state == :analyzing_final
    assert Repo.reload!(context.final_analysis).result_ref == nil
  end
end
