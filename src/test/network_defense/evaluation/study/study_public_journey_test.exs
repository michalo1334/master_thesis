defmodule NetworkDefense.Evaluation.Study.PublicJourneyTest do
  use NetworkDefense.DataCase, async: false

  import Ecto.Query

  alias NetworkDefense.Evaluation.EvidenceSnapshots
  alias NetworkDefense.Evaluation.Final.Contracts.Request, as: FinalRequest
  alias NetworkDefense.Evaluation.Final.Workflow, as: FinalWorkflow
  alias NetworkDefense.Evaluation.FinalConformance
  alias NetworkDefense.Evaluation.Pilot.Contracts.{PilotResult, Recommendation}
  alias NetworkDefense.Evaluation.Pilot.Workflow, as: PilotWorkflow

  alias NetworkDefense.Evaluation.Study.{
    Collection,
    CollectionItems,
    CollectionWorkflow,
    FinalTierWorkflow,
    Revisions
  }

  alias NetworkDefense.Evaluation.Study.{CompactResult, PilotOutcome, PilotSnapshot}
  alias NetworkDefense.Evaluation.Study.Contracts.{Definition, StudyError}
  alias NetworkDefense.Evaluation.Study.Timing.{Interval, ReplicaTiming, TimingSummary}

  alias NetworkDefense.Evaluation.{
    StudyCollectionItem,
    StudyExecution,
    StudyFixtures,
    StudyPhase,
    StudyPhaseRun,
    StudyResult
  }

  alias NetworkDefense.Evaluations

  # The two required public journeys:
  #
  #   STUDY-JOURNEY-01  a recommended Pilot pauses, resumes with `:recommended`,
  #                     completes Final analysis, and returns one compact result
  #                     with `pilot_override: false`
  #   STUDY-JOURNEY-02  an insufficient Pilot rejects `:recommended`, accepts the
  #                     declared override, completes Final analysis, and returns
  #                     one compact result with `pilot_override: true`
  #
  # Both call only the public functions: `start_study/1`, `study_status/1`,
  # `resume_study/2`, and `study_result/1`. The real coordinator runs the
  # lifecycle, including its own fixed phase rows.
  #
  # The four fixed workflows are replaced at their Gust transport boundary with
  # `meck`, which is the seam the existing rescue suite uses. Run creation,
  # dispatch, waiting, and result storage are stand-ins. The coordinator, the
  # request builders, the snapshot checks, and the result validation are real.
  # The collection stand-in runs the real collection items, so the accepted
  # Pilot snapshot is real evidence.

  @workflow_modules [
    CollectionWorkflow,
    PilotWorkflow,
    FinalTierWorkflow,
    FinalWorkflow
  ]

  @coordinator_timeout 30_000

  defmodule Store do
    use Agent

    def start_link(value), do: Agent.start_link(fn -> value end, name: __MODULE__)
    def get(key), do: Agent.get(__MODULE__, &Map.fetch!(&1, key))
    def put(key, value), do: Agent.update(__MODULE__, &Map.put(&1, key, value))
  end

  setup do
    core = StudyFixtures.insert_collection_graph("study-journey-core", mission: true)
    edge = StudyFixtures.insert_collection_graph("study-journey-edge", mission: true)
    definition = StudyFixtures.conformance_journey_definition!(core, edge)
    final_fixture = StudyFixtures.final_conformance_fixture()

    revision =
      StudyFixtures.insert_revision(%{
        id: FinalConformance.request()["study_revision_id"],
        definition: Definition.to_params(definition)
      })

    {:ok, final_snapshot} =
      EvidenceSnapshots.create_final(FinalConformance.snapshot_input!(final_fixture))

    candidate = Enum.find(definition.pilot.candidates, &(&1.id == "medium"))

    start_supervised!(
      {Store,
       %{
         definition: definition,
         final_fixture: final_fixture,
         final_snapshot_id: final_snapshot.id,
         final_result: nil,
         pilot_snapshot_id: nil,
         pilot_result: {:ok, recommended(candidate)}
       }}
    )

    install_workflow_boundaries!()

    %{
      revision: revision,
      definition: definition,
      candidate: candidate,
      final_snapshot: final_snapshot
    }
  end

  test "STUDY-JOURNEY-01: WHEN a valid study produces a recommended Pilot, THE public API SHALL pause, resume with :recommended, complete Final analysis, and return one compact result with pilot_override false",
       context do
    assert {:ok, %StudyExecution{state: :collecting_pilot} = started} =
             Evaluations.start_study(context.revision.id)

    await_coordinator(started.id)

    assert {:ok, %StudyExecution{state: :awaiting_final} = paused} =
             Evaluations.study_status(started.id)

    assert {:ok, %PilotOutcome{outcome: :recommended, candidate_id: candidate_id}} =
             PilotOutcome.parse(paused.pilot_outcome)

    assert candidate_id == context.candidate.id

    assert {:ok, %StudyExecution{state: :collecting_final}} =
             Evaluations.resume_study(started.id, :recommended)

    await_coordinator(started.id)

    assert {:ok, %StudyExecution{state: :succeeded}} = Evaluations.study_status(started.id)

    assert {:ok, %CompactResult{} = compact} = Evaluations.study_result(started.id)

    assert compact.execution_id == started.id
    assert compact.study_revision_id == context.revision.id
    assert compact.selection.candidate_id == context.candidate.id
    assert compact.selection.pilot_override == false
    assert compact.pilot_analysis.outcome.outcome == :recommended
    assert compact.final_result.family_id == context.definition.family.id
    assert compact.final_result.family_size == length(context.definition.family.comparisons)
    assert Repo.aggregate(StudyResult, :count, :id) == 1

    assert_final_family!(started.id, context.definition, compact)
  end

  test "STUDY-JOURNEY-02: WHEN a valid study produces an insufficient Pilot, THE public API SHALL reject :recommended, accept the declared override, complete Final analysis, and return one compact result with pilot_override true",
       context do
    Store.put(:pilot_result, {:ok, insufficient()})

    assert {:ok, %StudyExecution{state: :collecting_pilot} = started} =
             Evaluations.start_study(context.revision.id)

    await_coordinator(started.id)

    assert {:ok, %StudyExecution{state: :awaiting_final}} = Evaluations.study_status(started.id)

    assert {:error, %StudyError{issues: [%{"code" => "invalid_final_selection"}]}} =
             Evaluations.resume_study(started.id, :recommended)

    assert {:ok, %StudyExecution{state: :awaiting_final}} = Evaluations.study_status(started.id)

    assert {:ok, %StudyExecution{state: :collecting_final}} =
             Evaluations.resume_study(
               started.id,
               {:override_insufficient, context.candidate.id}
             )

    await_coordinator(started.id)

    assert {:ok, %StudyExecution{state: :succeeded}} = Evaluations.study_status(started.id)

    assert {:ok, %CompactResult{} = compact} = Evaluations.study_result(started.id)

    assert compact.selection.candidate_id == context.candidate.id
    assert compact.selection.pilot_override == true
    assert compact.pilot_analysis.outcome.outcome == :insufficient
    assert Repo.aggregate(StudyResult, :count, :id) == 1

    assert_final_family!(started.id, context.definition, compact)
  end

  # The public lifecycle activates one timed tier run per declared tier, keeps
  # the Final collection phase scalar run nil, and stores the ordered run IDs.
  defp assert_final_family!(execution_id, definition, compact) do
    phase = Repo.get_by!(StudyPhase, execution_id: execution_id, phase: :final_collection)
    assert is_nil(phase.gust_run_id)
    assert is_binary(phase.snapshot_id)

    tiers = definition.family.comparisons |> Enum.map(& &1.tier) |> Enum.uniq()

    phase_runs =
      Repo.all(
        from run in StudyPhaseRun,
          where: run.study_phase_id == ^phase.id,
          order_by: run.tier_position
      )

    assert Enum.map(phase_runs, & &1.tier) == tiers
    assert length(phase_runs) == length(tiers)
    assert Enum.map(phase_runs, & &1.tier_position) == Enum.to_list(0..(length(tiers) - 1))
    assert Enum.all?(phase_runs, &(is_integer(&1.gust_run_id) and &1.gust_run_id > 0))

    positions =
      Repo.all(
        from item in StudyCollectionItem,
          where: item.study_phase_id == ^phase.id,
          distinct: item.replica_position,
          select: item.replica_position
      )

    assert Enum.sort(positions) == [-1, 0, 1, 2, 3, 4]
    assert compact.final_collection.gust_run_ids == Enum.map(phase_runs, & &1.gust_run_id)
    assert length(compact.final_collection.gust_run_ids) == length(tiers)

    # The accepted timing family holds one summary per declared tier, in
    # declared order, with warm-up excluded.
    assert %TimingSummary{tiers: timing_tiers} = compact.timing
    assert Enum.map(timing_tiers, & &1.tier) == tiers
    assert Enum.map(timing_tiers, & &1.tier_position) == Enum.to_list(0..(length(tiers) - 1))

    for %{plan_selection: plan, simulation: simulation, total: total} <- timing_tiers,
        duration <- [plan, simulation, total] do
      assert duration.values_us == [1, 1, 1, 1, 1]
      assert duration.median_us == 1
      assert duration.minimum_us == 1
      assert duration.maximum_us == 1
    end
  end

  # The coordinator owns the activation boundary: it registers the execution
  # before the first workflow call and exits after the last commit. Monitoring
  # that process therefore waits for the committed work without polling.
  defp await_coordinator(execution_id) do
    case Registry.lookup(NetworkDefense.Evaluation.Study.CoordinatorRegistry, execution_id) do
      [{pid, _value}] ->
        reference = Process.monitor(pid)
        assert_receive {:DOWN, ^reference, :process, ^pid, _reason}, @coordinator_timeout

      [] ->
        :ok
    end
  end

  defp install_workflow_boundaries! do
    for module <- @workflow_modules do
      :meck.new(module, [:passthrough, :no_link])
      :meck.expect(module, :dispatch, fn _run_id -> :ok end)
    end

    :meck.expect(CollectionWorkflow, :create, &collect_pilot!/1)

    :meck.expect(CollectionWorkflow, :await, fn _run_id ->
      {:ok, Store.get(:pilot_snapshot_id)}
    end)

    :meck.expect(PilotWorkflow, :create, fn _params -> {:ok, 802} end)
    :meck.expect(PilotWorkflow, :await, fn _run_id -> {:ok, :succeeded} end)
    :meck.expect(PilotWorkflow, :result, fn _run_id -> Store.get(:pilot_result) end)

    :meck.expect(FinalTierWorkflow, :create, &create_tier_run/1)

    :meck.expect(FinalTierWorkflow, :dispatch, fn _run_id -> :ok end)

    :meck.expect(FinalTierWorkflow, :await, fn _execution, phase_run, _timeout ->
      {:ok, tier_timings(phase_run.tier)}
    end)

    :meck.expect(FinalWorkflow, :create, &prepare_final_result/1)
    :meck.expect(FinalWorkflow, :await, fn _run_id -> {:ok, :succeeded} end)
    :meck.expect(FinalWorkflow, :result, fn _run_id -> {:ok, Store.get(:final_result)} end)

    on_exit(fn -> Enum.each(@workflow_modules, &:meck.unload/1) end)
  end

  defp collect_pilot!(phase) do
    execution = Repo.get!(StudyExecution, phase.execution_id)
    definition = Store.get(:definition)
    items = StudyFixtures.collect_pilot_items(execution, phase, definition)

    {:ok, snapshot_id} =
      PilotSnapshot.assemble_and_store_pilot_snapshot(phase, items, definition)

    Store.put(:pilot_snapshot_id, snapshot_id)
    {:ok, 801}
  end

  # The tier stand-in replaces only the Gust boundary: dispatch runs the real
  # application collection for every declared replica position of the tier.
  defp create_tier_run(phase_run) do
    run_id = 902 + phase_run.tier_position
    collect_tier_for(phase_run)
    {:ok, run_id}
  end

  defp collect_tier_for(phase_run) do
    phase = Repo.get!(StudyPhase, phase_run.study_phase_id)
    execution = Repo.get!(StudyExecution, phase.execution_id)
    {:ok, definition} = Revisions.load_definition(execution.study_revision_id)

    Enum.each(-1..4, fn position ->
      {:ok, work} = Collection.build_collection_work(execution, phase, definition, position)
      {:ok, tier_work} = Collection.filter_tier(work, definition, phase_run.tier)

      Enum.each(tier_work, fn work_item ->
        {:ok, item} = CollectionItems.get_or_create(phase.id, position, work_item.item_position)
        {:ok, _result} = Collection.run_collection_item(item.id)
      end)
    end)
  end

  defp tier_timings(tier) do
    interval = %Interval{elapsed_us: 1}

    Enum.map(0..4, fn position ->
      {:ok, timing} =
        ReplicaTiming.new(%{
          tier: tier,
          position: position,
          plan_selection: interval,
          simulation: interval,
          total: interval
        })

      timing
    end)
  end

  defp prepare_final_result(params) do
    with {:ok, %FinalRequest{} = request} <- FinalRequest.parse(params) do
      Store.put(:final_result, FinalConformance.result!(request, Store.get(:final_fixture)))
      {:ok, 903}
    end
  end

  defp recommended(candidate) do
    %PilotResult{
      outcome: "recommended",
      recommendation: %Recommendation{
        candidate_id: candidate.id,
        plan_count: candidate.plan_count_per_side,
        attacks_per_plan: candidate.attacks_per_plan
      }
    }
  end

  defp insufficient do
    %PilotResult{outcome: "insufficient", insufficient_reason: "no_passing_candidate"}
  end
end
