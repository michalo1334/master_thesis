defmodule NetworkDefense.Evaluation.Study.FinalCoordinatorTest do
  use NetworkDefense.DataCase, async: false

  import Ecto.Query

  alias NetworkDefense.Evaluation.Final.Contracts.{FinalError, Request}
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError

  alias NetworkDefense.Evaluation.Study.{
    Coordinator,
    Results
  }

  alias NetworkDefense.Evaluation.Study.Cancel

  alias NetworkDefense.Evaluation.Study.PhaseRuns
  alias NetworkDefense.Evaluation.Study.Timing.Canonical
  alias NetworkDefense.Evaluation.Study.Timing.{TierTiming, TimingSummary}

  alias NetworkDefense.Evaluation.{
    EvidenceSnapshot,
    FinalConformance,
    PilotConformance,
    StudyCollectionItem,
    StudyExecution,
    StudyFixtures,
    StudyPhase,
    StudyPhaseRun,
    StudyResult
  }

  alias NetworkDefense.Simulation.Run, as: SimulationRun

  defmodule Store do
    use Agent

    def start_link(value), do: Agent.start_link(fn -> value end, name: __MODULE__)
    def get(key), do: Agent.get(__MODULE__, &Map.fetch!(&1, key))
    def put(key, value), do: Agent.update(__MODULE__, &Map.put(&1, key, value))
    def fetch(key, default), do: Agent.get(__MODULE__, &Map.get(&1, key, default))
  end

  defmodule ReplicaTimingStub do
    alias NetworkDefense.Evaluation.Study.Timing.{Interval, ReplicaTiming}

    # Each tier holds distinct measured values, so a summary proves the tier's own
    # timings were used in declared tier order.
    def timings(tier) do
      offset = if tier == "core", do: 100, else: 900

      Enum.map(0..4, fn position ->
        {:ok, timing} =
          ReplicaTiming.new(%{
            tier: tier,
            position: position,
            plan_selection: %Interval{elapsed_us: offset + position},
            simulation: %Interval{elapsed_us: offset + 50 + position},
            total: %Interval{elapsed_us: offset + 200 + position}
          })

        timing
      end)
    end
  end

  # The tier workflow stand-in replaces only the Gust boundary. Creation runs the
  # real application collection for every declared replica position of the tier,
  # so the summaries hold authoritative PostgreSQL evidence. Creation stays
  # outside the coordinator database locks; dispatch and await keep their shape.
  defmodule FinalTierWorkflowStub do
    alias NetworkDefense.Evaluation.Study.{Collection, CollectionItems, Revisions}
    alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase}
    alias NetworkDefense.Repo

    # The stand-in compresses the tier work into creation, which runs outside the
    # coordinator database locks. Dispatch and await keep their shape.
    def create(phase_run) do
      send(Store.get(:owner), {:tier_created, phase_run.tier, phase_run.tier_position})

      if Store.fetch(:block_create, nil) == phase_run.tier do
        receive do
          :continue_create -> :ok
        end
      end

      if Store.fetch(:collect, false) do
        collect!(phase_run)

        case Store.fetch({:mutate_after_collect, phase_run.tier}, nil) do
          nil -> :ok
          fun -> fun.()
        end
      end

      run_id = Store.get(:next_run_id)
      Store.put(:next_run_id, run_id + 1)
      {:ok, run_id}
    end

    def dispatch(run_id) do
      phase_run = Repo.get_by!(StudyPhaseRun, gust_run_id: run_id)
      send(Store.get(:owner), {:tier_dispatched, phase_run.tier, run_id})
      :ok
    end

    def await(_execution, phase_run, _timeout) do
      send(Store.get(:owner), {:tier_waiting, phase_run.tier, self()})

      if Store.fetch(:block_await, nil) == phase_run.tier do
        receive do
          :continue_tier -> :ok
        end
      end

      case Store.fetch({:tier_result, phase_run.tier}, nil) do
        nil -> {:ok, timings(phase_run.tier)}
        result -> result
      end
    end

    defp timings(tier), do: ReplicaTimingStub.timings(tier)

    defp collect!(phase_run) do
      phase = Repo.get!(StudyPhase, phase_run.study_phase_id)
      execution = Repo.get!(StudyExecution, phase.execution_id)
      {:ok, definition} = Revisions.load_definition(execution.study_revision_id)

      Enum.each(-1..4, fn position ->
        {:ok, work} =
          Collection.build_collection_work(execution, phase, definition, position)

        {:ok, tier_work} = Collection.filter_tier(work, definition, phase_run.tier)

        Enum.each(tier_work, fn work_item ->
          {:ok, item} =
            CollectionItems.get_or_create(phase.id, position, work_item.item_position)

          {:ok, _result} = Collection.run_collection_item(item.id)
        end)
      end)
    end
  end

  defmodule FinalWorkflowStub do
    def create(params) do
      with {:ok, %Request{} = request} <- Request.parse(params) do
        Store.put(:rows_at_analysis, final_phase_rows())
        Store.put(:final_result, FinalConformance.result!(request, Store.get(:fixture)))
        send(Store.get(:owner), {:final_analysis_created, request})
        {:ok, 903}
      end
    end

    def dispatch(903) do
      send(Store.get(:owner), :final_analysis_dispatched)
      :ok
    end

    def await(903) do
      if Store.get(:block_analysis) do
        send(Store.get(:owner), {:final_analysis_waiting, self()})
        receive do: (:continue_final_analysis -> :ok)
      end

      Store.get(:analysis_result)
    end

    def result(903), do: {:ok, Store.get(:final_result)}

    # The stored Final tier family at the moment Final analysis is created.
    defp final_phase_rows do
      import Ecto.Query

      Repo.all(
        from run in StudyPhaseRun,
          join: phase in StudyPhase,
          on: phase.id == run.study_phase_id,
          where: phase.phase == :final_collection,
          order_by: run.tier_position,
          select: {run.tier, run.gust_run_id}
      )
    end
  end

  # Places a real cancellation between immutable evidence assembly and snapshot
  # acceptance, so the accepted-evidence invariant is exercised without timing
  # assumptions.
  defmodule CancelBeforeAcceptSnapshot do
    alias NetworkDefense.Evaluation.Study.{Cancel, FinalSnapshot}

    def assemble_and_store(phase, items, definition) do
      FinalSnapshot.assemble_and_store(phase, items, definition,
        on_prepared: fn ->
          {:ok, _cancelled} = Cancel.cancel(phase.execution_id)
        end
      )
    end
  end

  setup do
    core = StudyFixtures.insert_collection_graph("study-final-coordinator-core", mission: true)
    edge = StudyFixtures.insert_collection_graph("study-final-coordinator-edge", mission: true)
    definition = StudyFixtures.conformance_journey_definition!(core, edge)
    fixture = StudyFixtures.final_conformance_fixture()
    context = StudyFixtures.final_lifecycle(definition, pilot_run_id: 901)

    {:ok, pilot_snapshot} = PilotConformance.store_snapshot(PilotConformance.snapshot())

    pilot_collection = StudyFixtures.insert_phase(context.execution, :pilot_collection)

    pilot_collection
    |> StudyPhase.changeset(%{gust_run_id: 801, snapshot_id: pilot_snapshot.id})
    |> Repo.update!()

    start_supervised!(
      {Store,
       %{
         owner: self(),
         next_run_id: 902,
         collect: true,
         block_analysis: false,
         analysis_result: {:ok, :succeeded},
         final_result: nil,
         fixture: fixture,
         select_calls: 0
       }}
    )

    Map.merge(context, %{definition: definition, fixture: fixture})
  end

  test "C-01: WHEN Final collection runs, THE coordinator SHALL create one ordered tier run per declared tier and complete the public lifecycle",
       context do
    count_selector_calls!()

    assert :ok = run(context.execution.id)

    # Tiers run sequentially in first-seen comparison order.
    for {tier, tier_position} <- [{"core", 0}, {"edge", 1}] do
      assert_receive {:tier_created, ^tier, ^tier_position}
      assert_receive {:tier_dispatched, ^tier, run_id}
      assert run_id == 902 + tier_position
      assert_receive {:tier_waiting, ^tier, _pid}
    end

    phase_rows =
      from(run in StudyPhaseRun,
        where: run.study_phase_id == ^context.final_phase.id,
        order_by: run.tier_position
      )
      |> Repo.all()

    assert [_, _] = phase_rows
    assert Enum.map(phase_rows, & &1.tier) == ["core", "edge"]
    assert Enum.map(phase_rows, & &1.tier_position) == [0, 1]
    assert Enum.map(phase_rows, & &1.gust_run_id) == [902, 903]
    assert is_nil(Repo.get!(StudyPhase, context.final_phase.id).gust_run_id)

    # Warm-up and every measured position hold stored rows for each tier.
    positions =
      from(item in StudyCollectionItem,
        where: item.study_phase_id == ^context.final_phase.id,
        distinct: item.replica_position,
        select: item.replica_position
      )
      |> Repo.all()

    assert Enum.sort(positions) == [-1, 0, 1, 2, 3, 4]

    # The Final snapshot holds replica-position-zero rows only.
    snapshot_id = Repo.get!(StudyPhase, context.final_phase.id).snapshot_id
    assert is_binary(snapshot_id)
    assert %EvidenceSnapshot{phase: :final} = Repo.get!(EvidenceSnapshot, snapshot_id)

    execution = Repo.get!(StudyExecution, context.execution.id)
    assert execution.state == :succeeded

    # Final analysis starts only after the tier family and equality gate.
    assert Store.get(:rows_at_analysis) == [{"core", 902}, {"edge", 903}]
    assert_received {:final_analysis_created, request}
    assert request.snapshot_id == snapshot_id
    assert Repo.get_by!(StudyPhase, execution_id: execution.id, phase: :final_analysis)

    assert {:ok, compact} = Results.get_for_execution(execution.id)
    assert compact.pilot_collection.gust_run_ids == [801]
    assert compact.final_collection.gust_run_ids == [902, 903]
    assert compact.final_collection.snapshot_id == snapshot_id

    assert %TimingSummary{tiers: [%TierTiming{tier: "core"}, %TierTiming{tier: "edge"}]} =
             compact.timing

    # One canonical selector call accepts the measured family.
    assert Store.get(:select_calls) == 1
  end

  test "T5-12: WHEN the accepted timing family reaches Final result creation, THE stored result SHALL hold one summary per declared tier in declared order",
       context do
    assert :ok = run(context.execution.id)

    assert {:ok, compact} = Results.get_for_execution(context.execution.id)

    assert [
             %TierTiming{tier: "core", tier_position: 0} = core,
             %TierTiming{tier: "edge", tier_position: 1} = edge
           ] = compact.timing.tiers

    assert core.plan_selection.values_us == [100, 101, 102, 103, 104]
    assert core.plan_selection.median_us == 102
    assert core.simulation.values_us == [150, 151, 152, 153, 154]
    assert core.total.maximum_us == 304

    assert edge.plan_selection.values_us == [900, 901, 902, 903, 904]
    assert edge.simulation.median_us == 952
    assert edge.total.values_us == [1_100, 1_101, 1_102, 1_103, 1_104]
  end

  test "C-13: WHEN cancellation commits between evidence assembly and snapshot acceptance, THE coordinator SHALL keep cancelled and store no Final evidence",
       context do
    assert :ok =
             Coordinator.run(context.execution.id,
               final_tier_workflow: FinalTierWorkflowStub,
               final_workflow: FinalWorkflowStub,
               final_snapshot: CancelBeforeAcceptSnapshot
             )

    execution = Repo.get!(StudyExecution, context.execution.id)
    assert execution.state == :cancelled
    assert execution.error == nil

    phase = Repo.get!(StudyPhase, context.final_phase.id)
    assert is_nil(phase.snapshot_id)
    assert is_nil(phase.error)

    assert Repo.all(from snapshot in EvidenceSnapshot, where: snapshot.phase == :final) == []
    refute Repo.get_by(StudyPhase, execution_id: execution.id, phase: :final_analysis)
    refute_received {:final_analysis_created, _request}
    assert Repo.aggregate(StudyResult, :count, :id) == 0
  end

  test "C-01: WHEN the Final collection phase still holds a legacy scalar run, THE coordinator SHALL fail before any tier starts",
       context do
    context.final_phase
    |> StudyPhase.changeset(%{gust_run_id: 700})
    |> Repo.update!()

    assert {:error, %StudyError{issues: [issue]}} = run(context.execution.id)
    assert issue["code"] == "incomplete_final_family"

    refute_received {:tier_created, _tier, _position}
    assert Repo.get!(StudyExecution, context.execution.id).state == :failed

    phase_rows =
      Repo.all(
        from run in StudyPhaseRun,
          where: run.study_phase_id == ^context.final_phase.id
      )

    assert phase_rows == []
    assert Repo.aggregate(StudyResult, :count, :id) == 0
  end

  test "C-03: WHEN cancellation commits before dispatch, THE coordinator SHALL not dispatch that tier",
       context do
    Store.put(:block_create, "core")

    task = Task.async(fn -> run(context.execution.id) end)
    assert_receive {:tier_created, "core", 0}, 5_000

    context.execution
    |> Repo.reload!()
    |> StudyExecution.changeset(%{state: :cancelled})
    |> Repo.update!()

    send(task.pid, :continue_create)

    assert Task.await(task, 5_000) == :ok
    refute_received {:tier_dispatched, "core", _run_id}
    refute_received {:tier_created, "edge", _position}

    execution = Repo.get!(StudyExecution, context.execution.id)
    assert execution.state == :cancelled
    assert is_nil(Repo.get!(StudyPhase, context.final_phase.id).snapshot_id)
    assert Repo.aggregate(StudyResult, :count, :id) == 0
  end

  test "C-04: WHEN cancellation commits during a tier run, THE execution SHALL remain cancelled and no later tier SHALL start",
       context do
    Store.put(:block_await, "core")

    task = Task.async(fn -> run(context.execution.id) end)
    assert_receive {:tier_waiting, "core", _pid}, 5_000

    context.execution
    |> Repo.reload!()
    |> StudyExecution.changeset(%{state: :cancelled})
    |> Repo.update!()

    send(task.pid, :continue_tier)

    assert Task.await(task, 5_000) == :ok
    refute_received {:tier_created, "edge", _position}

    execution = Repo.get!(StudyExecution, context.execution.id)
    assert execution.state == :cancelled
    assert is_nil(Repo.get!(StudyPhase, context.final_phase.id).snapshot_id)
    assert Repo.aggregate(StudyResult, :count, :id) == 0
  end

  test "C-02: WHEN a tier does not return five measured timing values, THE coordinator SHALL not start the next tier",
       context do
    Store.put(:collect, false)

    Store.put(
      {:tier_result, "core"},
      {:ok, Enum.take(ReplicaTimingStub.timings("core"), 4)}
    )

    assert {:error, %StudyError{issues: [issue]}} = run(context.execution.id)
    assert issue["code"] == "final_timing_incomplete"
    assert Repo.get!(StudyExecution, context.execution.id).state == :failed

    phase_rows =
      from(run in StudyPhaseRun,
        where: run.study_phase_id == ^context.final_phase.id,
        order_by: run.tier_position
      )
      |> Repo.all()

    assert Enum.map(phase_rows, & &1.tier) == ["core"]
  end

  test "C-01: WHEN a phase-run row already links a Gust run, THE coordinator SHALL dispatch that run instead of creating a second one",
       context do
    Store.put(:collect, false)
    Store.put({:tier_result, "core"}, {:error, StudyError.final_timing_incomplete()})

    {:ok, row} = PhaseRuns.get_or_create(context.final_phase, "core", 0)
    {:ok, linked} = PhaseRuns.link_gust_run(row, 700)
    assert linked.gust_run_id == 700

    assert {:error, %StudyError{}} = run(context.execution.id)

    refute_received {:tier_created, "core", 0}
    assert_received {:tier_dispatched, "core", 700}
  end

  test "C-05: WHEN a later tier fails, THE execution SHALL fail and earlier tier rows SHALL remain stored",
       context do
    Store.put(:collect, false)
    Store.put({:tier_result, "edge"}, {:error, StudyError.final_timing_incomplete()})

    assert {:error, %StudyError{}} = run(context.execution.id)

    execution = Repo.get!(StudyExecution, context.execution.id)
    assert execution.state == :failed
    assert execution.error == Repo.get!(StudyPhase, context.final_phase.id).error

    phase_rows =
      from(run in StudyPhaseRun,
        where: run.study_phase_id == ^context.final_phase.id,
        order_by: run.tier_position
      )
      |> Repo.all()

    assert Enum.map(phase_rows, & &1.tier) == ["core", "edge"]
    assert Enum.map(phase_rows, & &1.gust_run_id) == [902, 903]
    assert is_nil(Repo.get!(StudyPhase, context.final_phase.id).snapshot_id)
    assert Repo.aggregate(StudyResult, :count, :id) == 0
  end

  test "C-10: WHEN one measured summary differs, THE execution SHALL fail without a replacement replica or snapshot",
       context do
    Store.put({:mutate_after_collect, "core"}, fn -> change_one_measured_plan(context) end)

    assert {:error, %StudyError{} = error} = run(context.execution.id)
    assert error.code == "conflict"
    assert Enum.any?(error.issues, &(&1["code"] == "final_replica_mismatch"))

    execution = Repo.get!(StudyExecution, context.execution.id)
    assert execution.state == :failed
    assert is_nil(Repo.get!(StudyPhase, context.final_phase.id).snapshot_id)
    refute_received {:final_analysis_created, _request}

    # All stored rows of the rejected replica set remain for inspection.
    positions =
      from(item in StudyCollectionItem,
        where: item.study_phase_id == ^context.final_phase.id,
        distinct: item.replica_position,
        select: item.replica_position
      )
      |> Repo.all()

    assert Enum.sort(positions) == [-1, 0, 1, 2, 3, 4]
  end

  test "F21-02: WHEN cancellation commits before late Final completion, THE coordinator SHALL keep cancelled and store no compact result",
       context do
    Store.put(:block_analysis, true)

    task = Task.async(fn -> run(context.execution.id) end)
    assert_receive {:final_analysis_waiting, coordinator_pid}, 10_000

    context.execution
    |> Repo.reload!()
    |> StudyExecution.changeset(%{state: :cancelled})
    |> Repo.update!()

    send(coordinator_pid, :continue_final_analysis)
    assert Task.await(task, 5_000) == :ok

    assert Repo.get!(StudyExecution, context.execution.id).state == :cancelled
    assert Repo.aggregate(StudyResult, :count, :id) == 0
  end

  test "F21-03: WHEN Final collection fails terminally, THE coordinator SHALL store one bounded error without a result",
       context do
    Store.put(:collect, false)
    Store.put({:tier_result, "core"}, {:error, StudyError.final_collection_workflow_failed()})

    assert {:error, %StudyError{}} = run(context.execution.id)

    execution = Repo.get!(StudyExecution, context.execution.id)
    phase = Repo.get!(StudyPhase, context.final_phase.id)
    assert execution.state == :failed
    assert execution.error == phase.error
    assert Jason.encode!(execution.error) =~ "final_collection_workflow_failed"
    assert Repo.aggregate(StudyResult, :count, :id) == 0
  end

  test "F21-03: WHEN Final analysis fails terminally, THE coordinator SHALL store one bounded error without a result",
       context do
    Store.put(:analysis_result, {:error, FinalError.workflow_failed()})

    assert {:error, %StudyError{}} = run(context.execution.id)

    execution = Repo.get!(StudyExecution, context.execution.id)
    phase = Repo.get_by!(StudyPhase, execution_id: execution.id, phase: :final_analysis)
    assert execution.state == :failed
    assert execution.error == phase.error
    assert Jason.encode!(execution.error) =~ "final_analysis_failed"
    assert Repo.aggregate(StudyResult, :count, :id) == 0
  end

  # Changes one stored trial of measured position 1 without making the evidence
  # malformed, so the five summaries keep their shape and differ in value.
  defp change_one_measured_plan(context) do
    item =
      from(item in StudyCollectionItem,
        where: item.study_phase_id == ^context.final_phase.id and item.replica_position == 1,
        order_by: item.item_position,
        limit: 1
      )
      |> Repo.one!()

    run =
      from(run in SimulationRun,
        where: run.experiment_id == ^item.experiment_id,
        order_by: run.trial_index,
        limit: 1
      )
      |> Repo.one!()

    state = run.initial_attacker_state

    privileges =
      Map.new(state.privileges, fn {host_id, _privilege} -> {host_id, "administrator"} end)

    run
    |> Ecto.Changeset.change(initial_attacker_state: %{privileges: privileges})
    |> Repo.update!()

    :ok
  end

  defp count_selector_calls! do
    :meck.new(Canonical, [:passthrough, :no_link])

    :meck.expect(Canonical, :select, fn replicas ->
      Store.put(:select_calls, Store.get(:select_calls) + 1)
      :meck.passthrough([replicas])
    end)

    on_exit(fn -> :meck.unload(Canonical) end)
  end

  defp run(execution_id) do
    Coordinator.run(execution_id,
      final_tier_workflow: FinalTierWorkflowStub,
      final_workflow: FinalWorkflowStub
    )
  end
end
