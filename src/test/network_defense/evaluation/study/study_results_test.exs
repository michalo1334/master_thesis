defmodule NetworkDefense.Evaluation.Study.ResultsTest do
  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Evaluation.Study.{
    CompactResult,
    FinalRequest,
    FinalSelection,
    PhaseRuns,
    PilotOutcome,
    Results
  }

  alias NetworkDefense.Evaluation.Study.CompactResult.{
    AnalysisReference,
    CollectionReference,
    PilotAnalysisReference
  }

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError

  alias NetworkDefense.Evaluation.Study.Timing.{Interval, ReplicaTiming, TimingSummary}

  alias NetworkDefense.Evaluation.{
    FinalConformance,
    PilotConformance,
    StudyExecution,
    StudyFixtures,
    StudyPhase,
    StudyPhaseRun,
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

    context = StudyFixtures.accept_final_collection!(context, final_snapshot.id)

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
      request: request,
      timing: timing_summary(context.definition)
    })
  end

  test "F21-01: WHEN Final analysis returns one valid complete family, THE application SHALL store one immutable compact result and succeed atomically",
       context do
    assert {:ok, %CompactResult{} = compact} =
             Results.create_success(context.execution, context.final_result, context.timing)

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

    assert compact.timing == context.timing

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

  test "C-14: WHEN a compact result is created, THE Pilot collection reference SHALL contain one run ID and THE Final collection reference SHALL contain the ordered tier-run IDs",
       context do
    assert {:ok, %CompactResult{} = compact} =
             Results.create_success(context.execution, context.final_result, context.timing)

    phase_runs =
      Repo.all(
        from run in StudyPhaseRun,
          where: run.study_phase_id == ^context.final_collection.id,
          order_by: run.tier_position
      )

    assert length(phase_runs) == length(context.definition.family.comparisons)
    assert compact.pilot_collection.gust_run_ids == [context.pilot_collection.gust_run_id]
    assert compact.final_collection.gust_run_ids == Enum.map(phase_runs, & &1.gust_run_id)
    assert is_nil(Repo.get!(StudyPhase, context.final_collection.id).gust_run_id)

    params = CompactResult.to_params(compact)
    assert params["final_collection"]["gust_run_ids"] == Enum.map(phase_runs, & &1.gust_run_id)
    refute Map.has_key?(params["final_collection"], "gust_run_id")
  end

  test "C-15: WHEN a compact result is read, THE stored run-ID lists SHALL match the authoritative phase and phase-run rows",
       context do
    assert {:ok, %CompactResult{} = compact} =
             Results.create_success(context.execution, context.final_result, context.timing)

    assert {:ok, ^compact} = Results.get_for_execution(context.execution.id)

    # The stored list must match the authoritative ordered phase-run rows.
    Repo.get_by!(StudyPhaseRun, study_phase_id: context.final_collection.id, tier_position: 1)
    |> Repo.delete!()

    assert Results.get_for_execution(context.execution.id) ==
             {:error, StudyError.result_unavailable()}
  end

  test "C-15: WHEN the authoritative tier rows change after creation, THE stored run-ID list SHALL be rejected on read",
       context do
    assert {:ok, %CompactResult{} = compact} =
             Results.create_success(context.execution, context.final_result, context.timing)

    [first, second | _rest] = ordered_runs(context.final_collection.id)
    assert compact.final_collection.gust_run_ids == [first.gust_run_id, second.gust_run_id]

    # One authoritative run ID no longer matches the stored list.
    second
    |> Ecto.Changeset.change(%{gust_run_id: second.gust_run_id + 500})
    |> Repo.update!()

    assert Results.get_for_execution(context.execution.id) ==
             {:error, StudyError.result_unavailable()}

    # Restored rows match again; the same runs in a different order do not.
    second
    |> Repo.reload!()
    |> Ecto.Changeset.change(%{gust_run_id: second.gust_run_id})
    |> Repo.update!()

    assert {:ok, ^compact} = Results.get_for_execution(context.execution.id)

    first |> Ecto.Changeset.change(%{tier_position: 99}) |> Repo.update!()

    assert Results.get_for_execution(context.execution.id) ==
             {:error, StudyError.result_unavailable()}
  end

  test "C-16: WHEN a result carries the removed scalar collection field or an invalid run-ID list, THE strict parser SHALL reject it",
       context do
    assert {:ok, compact} =
             Results.create_success(context.execution, context.final_result, context.timing)

    params = CompactResult.to_params(compact)

    [first_run_id | _rest_run_ids] = params["final_collection"]["gust_run_ids"]

    invalid_payloads = [
      params
      |> put_in(["final_collection", "gust_run_id"], first_run_id)
      |> Map.update!("final_collection", &Map.delete(&1, "gust_run_ids")),
      put_in(params, ["final_collection", "gust_run_ids"], []),
      put_in(params, ["final_collection", "gust_run_ids"], [0]),
      put_in(params, ["final_collection", "gust_run_ids"], [first_run_id, -1]),
      put_in(params, ["final_collection", "gust_run_ids"], [first_run_id, first_run_id]),
      put_in(params, ["pilot_collection", "gust_run_ids"], "not-a-list")
    ]

    for invalid <- invalid_payloads do
      assert {:error, error} = CompactResult.parse(invalid)
      assert error == StudyError.final_result_invalid()
    end
  end

  test "F21-04: WHEN a result exists for a succeeded execution, THE application SHALL return the typed compact result; otherwise it SHALL return result_unavailable",
       context do
    assert {:error, %StudyError{} = unavailable} =
             Results.get_for_execution(context.execution.id)

    assert unavailable == StudyError.result_unavailable()

    assert {:ok, created} =
             Results.create_success(context.execution, context.final_result, context.timing)

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

    assert {:error, error} = Results.create_success(context.execution, invalid, context.timing)
    assert error == StudyError.final_result_invalid()
    assert Repo.aggregate(StudyResult, :count, :id) == 0
    assert Repo.reload!(context.execution).state == :analyzing_final
    assert Repo.reload!(context.final_analysis).result_ref == nil
  end

  test "F21-06: WHEN a compact payload contains a contradictory rejection decision, THE parser SHALL reject it",
       context do
    assert {:ok, compact} =
             Results.create_success(context.execution, context.final_result, context.timing)

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
    assert {:ok, compact} =
             Results.create_success(context.execution, context.final_result, context.timing)

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

    assert {:ok, created} =
             Results.create_success(context.execution, context.final_result, context.timing)

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

    assert {:error, error} =
             Results.create_success(context.execution, context.final_result, context.timing)

    assert error == StudyError.final_result_storage_failed()
    assert Repo.aggregate(StudyResult, :count, :id) == 1
    assert Repo.reload!(context.execution).state == :analyzing_final
    assert Repo.reload!(context.final_analysis).result_ref == nil
  end

  test "T5-12: WHEN Final analysis succeeds with valid timing, THE application SHALL persist one timing summary per declared tier inside the compact result",
       context do
    assert {:ok, %CompactResult{} = compact} =
             Results.create_success(context.execution, context.final_result, context.timing)

    assert %TimingSummary{tiers: [core, edge]} = compact.timing
    assert {core.tier, core.tier_position} == {"core", 0}
    assert {edge.tier, edge.tier_position} == {"edge", 1}

    for tier_timing <- [core, edge] do
      assert tier_timing.plan_selection.values_us == [100, 101, 102, 103, 104]
      assert tier_timing.plan_selection.median_us == 102
      assert tier_timing.simulation.values_us == [200, 201, 202, 203, 204]
      assert tier_timing.simulation.minimum_us == 200
      assert tier_timing.total.values_us == [300, 301, 302, 303, 304]
      assert tier_timing.total.maximum_us == 304
    end

    row = Repo.get_by!(StudyResult, execution_id: context.execution.id)
    assert [_, _] = row.data["timing"]["tiers"]

    assert row.data["timing"]["tiers"] |> hd() |> Map.keys() |> Enum.sort() ==
             ["plan_selection", "simulation", "tier", "tier_position", "total"] |> Enum.sort()

    assert {:ok, loaded} = Results.get_for_execution(context.execution.id)
    assert loaded.timing == compact.timing
  end

  test "T5-14: WHEN a newly created successful result has no timing summary, THE result boundary SHALL reject it without a row",
       context do
    refute function_exported?(Results, :create_success, 2)

    assert Results.create_success(context.execution, context.final_result, nil) ==
             {:error, StudyError.final_timing_incomplete()}

    assert Repo.aggregate(StudyResult, :count, :id) == 0
    assert Repo.reload!(context.execution).state == :analyzing_final
    assert Repo.reload!(context.final_analysis).result_ref == nil
  end

  test "T5-13: WHEN the timing summary does not follow the declared tier order, THE application SHALL reject success without a row",
       context do
    reversed = %TimingSummary{tiers: Enum.reverse(context.timing.tiers)}

    assert Results.create_success(context.execution, context.final_result, reversed) ==
             {:error, StudyError.final_timing_incomplete()}

    assert Repo.aggregate(StudyResult, :count, :id) == 0
    assert Repo.reload!(context.execution).state == :analyzing_final
  end

  test "T5-13: WHEN a constructed timing summary holds a malformed later tier item, THE result boundary SHALL return a bounded error without a row or state change",
       context do
    [core, _edge] = context.timing.tiers
    malformed = %TimingSummary{tiers: [core, nil]}

    assert Results.create_success(context.execution, context.final_result, malformed) ==
             {:error, StudyError.final_timing_incomplete()}

    assert Repo.aggregate(StudyResult, :count, :id) == 0
    assert Repo.reload!(context.execution).state == :analyzing_final
    assert Repo.reload!(context.final_analysis).result_ref == nil
  end

  test "T5-10: WHEN the timing summary holds derived values that differ from the measured values, THE application SHALL reject success without a row",
       context do
    [core, edge] = context.timing.tiers
    inconsistent = %{core.plan_selection | median_us: core.plan_selection.median_us + 1}
    invalid = %{context.timing | tiers: [%{core | plan_selection: inconsistent}, edge]}

    assert Results.create_success(context.execution, context.final_result, invalid) ==
             {:error, StudyError.final_result_invalid()}

    assert Repo.aggregate(StudyResult, :count, :id) == 0
  end

  test "T5-11: WHEN a schema-version-one result holds timing null, THE compact-result parser SHALL accept it and read-back SHALL return it",
       context do
    legacy_params = compact_params(context, nil)
    assert {:ok, %CompactResult{timing: nil}} = CompactResult.parse(legacy_params)

    # The legacy fixture is inserted directly; create_success/3 requires timing.
    insert_legacy_result!(context.execution, legacy_params)
    succeed_legacy_execution!(context)

    assert {:ok, %CompactResult{timing: nil} = loaded} =
             Results.get_for_execution(context.execution.id)

    assert loaded.execution_id == context.execution.id
    assert {:ok, %CompactResult{timing: nil}} = Evaluations.study_result(context.execution.id)
  end

  test "T5-16: WHEN a stored timing summary follows a different tier order, THE read-back boundary SHALL reject it",
       context do
    stored = compact_params(context, context.timing)

    reordered =
      update_in(stored, ["timing", "tiers"], fn [core, edge] ->
        [%{edge | "tier_position" => 0}, %{core | "tier_position" => 1}]
      end)

    # The reordered summary stays internally consistent, so only the declared
    # tier order rejects it on read-back.
    assert {:ok, %CompactResult{}} = CompactResult.parse(reordered)

    insert_legacy_result!(context.execution, reordered)
    succeed_legacy_execution!(context)

    assert Results.get_for_execution(context.execution.id) ==
             {:error, StudyError.result_unavailable()}
  end

  test "T5-16: WHEN a stored timing summary holds inconsistent statistics, THE read-back boundary SHALL reject it",
       context do
    stored = compact_params(context, context.timing)

    inconsistent =
      update_in(
        stored,
        ["timing", "tiers", Access.at(0), "total", "median_us"],
        &(&1 + 1)
      )

    assert {:error, error} = CompactResult.parse(inconsistent)
    assert error == StudyError.final_result_invalid()

    insert_legacy_result!(context.execution, inconsistent)
    succeed_legacy_execution!(context)

    assert Results.get_for_execution(context.execution.id) ==
             {:error, StudyError.result_unavailable()}
  end

  defp compact_params(context, timing) do
    {:ok, outcome} = PilotOutcome.parse(context.execution.pilot_outcome)
    {:ok, selection} = FinalSelection.from_execution(context.execution)
    {:ok, run_ids} = PhaseRuns.ordered_run_ids(context.final_collection.id)

    %CompactResult{
      study_revision_id: context.execution.study_revision_id,
      execution_id: context.execution.id,
      pilot_collection: %CollectionReference{
        phase_id: context.pilot_collection.id,
        gust_run_ids: [context.pilot_collection.gust_run_id],
        snapshot_id: context.pilot_collection.snapshot_id
      },
      pilot_analysis: %PilotAnalysisReference{
        phase_id: context.pilot_phase.id,
        gust_run_id: context.pilot_phase.gust_run_id,
        outcome: outcome
      },
      selection: selection,
      final_collection: %CollectionReference{
        phase_id: context.final_collection.id,
        gust_run_ids: run_ids,
        snapshot_id: context.final_collection.snapshot_id
      },
      final_analysis: %AnalysisReference{
        phase_id: context.final_analysis.id,
        gust_run_id: context.final_analysis.gust_run_id
      },
      final_result: context.final_result,
      revision_assertions: context.definition.study.revisions,
      timing: timing
    }
    |> CompactResult.to_params()
  end

  defp insert_legacy_result!(execution, params) do
    %StudyResult{}
    |> StudyResult.create_changeset(%{
      execution_id: execution.id,
      schema_version: 1,
      data: params
    })
    |> Repo.insert!()
  end

  defp succeed_legacy_execution!(context) do
    row = Repo.get_by!(StudyResult, execution_id: context.execution.id)

    context.execution
    |> Repo.reload!()
    |> StudyExecution.changeset(%{state: :succeeded})
    |> Repo.update!()

    context.final_analysis
    |> Repo.reload!()
    |> StudyPhase.changeset(%{result_ref: %{"study_result_id" => row.id}})
    |> Repo.update!()

    row
  end

  defp timing_summary(definition) do
    tiers = definition.family.comparisons |> Enum.map(& &1.tier) |> Enum.uniq()

    family =
      tiers
      |> Enum.with_index()
      |> Map.new(fn {tier, tier_position} ->
        {tier, %{tier_position: tier_position, timings: tier_timings(tier)}}
      end)

    {:ok, summary} = TimingSummary.summarize(tiers, family)
    summary
  end

  defp tier_timings(tier) do
    Enum.map(0..4, fn position ->
      {:ok, timing} =
        ReplicaTiming.new(%{
          tier: tier,
          position: position,
          plan_selection: %Interval{elapsed_us: 100 + position},
          simulation: %Interval{elapsed_us: 200 + position},
          total: %Interval{elapsed_us: 300 + position}
        })

      timing
    end)
  end

  defp ordered_runs(phase_id) do
    Repo.all(
      from run in StudyPhaseRun,
        where: run.study_phase_id == ^phase_id,
        order_by: run.tier_position
    )
  end
end
