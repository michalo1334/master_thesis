defmodule NetworkDefense.Evaluation.Study.StudyCoordinatorTest do
  use NetworkDefense.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.DAG.Loader.Worker, as: DagLoader
  alias NetworkDefense.Evaluation.Pilot.Contracts.{PilotError, PilotResult, Recommendation}
  alias NetworkDefense.Evaluation.{PilotConformance, StudyExecution, StudyFixtures, StudyPhase}
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.{Coordinator, PilotOutcome, PilotSnapshot}

  @failure_persistence_event [
    :network_defense,
    :evaluation,
    :study,
    :coordinator,
    :failure_persistence
  ]

  defmodule Store do
    use Agent

    def start_link(value), do: Agent.start_link(fn -> value end, name: __MODULE__)
    def get(key), do: Agent.get(__MODULE__, &Map.fetch!(&1, key))
    def put(key, value), do: Agent.update(__MODULE__, &Map.put(&1, key, value))

    def take(key) do
      Agent.get_and_update(__MODULE__, fn state -> Map.pop(state, key) end)
    end
  end

  defmodule CollectionWorkflowStub do
    def create(phase) do
      send(Store.get(:owner), {:collection_created, phase.id, self()})
      {:ok, 101}
    end

    def dispatch(101) do
      send(Store.get(:owner), {:collection_dispatched, self()})
      :ok
    end

    def await(101) do
      send(Store.get(:owner), {:collection_waiting, self()})

      if Store.get(:block_collection) do
        receive do
          :continue_collection -> :ok
        end
      end

      Store.get(:collection_result)
    end
  end

  defmodule PilotWorkflowStub do
    def create(params) do
      send(Store.get(:owner), {:pilot_created, params})

      if Store.get(:pause_analysis_accept) do
        Store.put(:pause_commit, :analysis)
      end

      {:ok, 202}
    end

    def dispatch(202) do
      send(Store.get(:owner), {:pilot_dispatched, self()})
      :ok
    end

    def await(202) do
      if Store.get(:block_pilot) do
        send(Store.get(:owner), {:pilot_waiting, self()})

        receive do
          :continue_pilot -> :ok
        end
      end

      Store.get(:pilot_await)
    end

    def result(202), do: Store.get(:pilot_result)
  end

  setup do
    collection = StudyFixtures.insert_collection_graph("study-coordinator", mission: true)
    definition = StudyFixtures.collection_definition(collection.graph, collection.foothold)
    study = StudyFixtures.study_with_two_phases(definition)

    collection_items =
      StudyFixtures.collect_pilot_items(study.execution, study.pilot_phase, definition)

    {:ok, snapshot_id} =
      PilotSnapshot.assemble_and_store_pilot_snapshot(
        study.pilot_phase,
        collection_items,
        definition
      )

    snapshot = Repo.get!(NetworkDefense.Evaluation.EvidenceSnapshot, snapshot_id)
    candidate = hd(definition.pilot.candidates)

    recommended = %PilotResult{
      outcome: "recommended",
      recommendation: %Recommendation{
        candidate_id: candidate.id,
        plan_count: candidate.plan_count_per_side,
        attacks_per_plan: candidate.attacks_per_plan
      }
    }

    start_supervised!(
      {Store,
       %{
         owner: self(),
         block_collection: false,
         block_pilot: false,
         pause_analysis_accept: false,
         collection_result: {:ok, snapshot.id},
         pilot_await: {:ok, :succeeded},
         pilot_result: {:ok, recommended}
       }}
    )

    Map.merge(study, %{
      definition: definition,
      snapshot: snapshot,
      recommended: recommended
    })
  end

  test "STUDY-COORD-01: recommendation persists compact references and stops at awaiting_final",
       context do
    assert :ok = run(context.execution.id)

    assert_receive {:collection_created, phase_id, _pid}
    assert phase_id == context.pilot_phase.id
    assert_receive {:collection_dispatched, _pid}
    assert_receive {:collection_waiting, _pid}
    assert_receive {:pilot_created, request}
    assert_receive {:pilot_dispatched, _pid}

    candidate = hd(context.definition.pilot.candidates)
    assert Enum.map(request["candidates"], & &1["id"]) == [candidate.id]
    assert hd(request["candidates"])["plan_count"] == candidate.plan_count_per_side

    execution = Repo.get!(StudyExecution, context.execution.id)
    assert execution.state == :awaiting_final
    assert {:ok, outcome} = PilotOutcome.parse(execution.pilot_outcome)
    assert outcome.candidate_id == candidate.id

    collection_phase = Repo.get!(StudyPhase, context.pilot_phase.id)
    assert collection_phase.gust_run_id == 101
    assert collection_phase.snapshot_id == context.snapshot.id

    analysis_phase = pilot_analysis_phase(context.execution)
    assert analysis_phase.gust_run_id == 202
    assert analysis_phase.result_ref == execution.pilot_outcome
  end

  test "STUDY-COORD-02: insufficiency is a valid awaiting-final outcome", context do
    replace_store(context, %{
      pilot_result:
        {:ok, %PilotResult{outcome: "insufficient", insufficient_reason: "no_passing_candidate"}}
    })

    assert :ok = run(context.execution.id)

    execution = Repo.get!(StudyExecution, context.execution.id)
    assert execution.state == :awaiting_final
    assert execution.error == nil

    assert execution.pilot_outcome == %{
             "outcome" => "insufficient",
             "reason" => "no_passing_candidate"
           }
  end

  test "STUDY-COORD-03: an active collection failure stores one bounded error", context do
    replace_store(context, %{collection_result: {:error, StudyError.collection_workflow_failed()}})

    assert {:error, %StudyError{}} = run(context.execution.id)

    execution = Repo.get!(StudyExecution, context.execution.id)
    phase = Repo.get!(StudyPhase, context.pilot_phase.id)

    assert execution.state == :failed
    assert execution.error == phase.error
    assert Jason.encode!(execution.error) =~ "collection_workflow_failed"
    refute Jason.encode!(execution.error) =~ "submitted"
  end

  test "STUDY-COORD-04: an active analysis failure stores one bounded error", context do
    replace_store(context, %{pilot_await: {:error, PilotError.workflow_failed()}})

    assert {:error, %StudyError{}} = run(context.execution.id)

    execution = Repo.get!(StudyExecution, context.execution.id)
    phase = pilot_analysis_phase(context.execution)

    assert execution.state == :failed
    assert execution.error == phase.error
    assert Jason.encode!(execution.error) =~ "pilot_analysis_failed"
  end

  test "STUDY-COORD-11: failure persistence emits one bounded telemetry event", context do
    owner = self()
    handler_id = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler_id,
        @failure_persistence_event,
        fn event, measurements, metadata, receiver ->
          send(receiver, {:failure_persistence, event, measurements, metadata})
        end,
        owner
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    replace_store(context, %{
      block_pilot: true,
      pilot_await: {:error, PilotError.workflow_failed()}
    })

    task = Task.async(fn -> run(context.execution.id) end)
    assert_receive {:pilot_waiting, coordinator_pid}, 2_000

    Repo.delete!(pilot_analysis_phase(context.execution))
    send(coordinator_pid, :continue_pilot)

    assert {:error,
            %StudyError{
              code: "unavailable",
              issues: [%{"code" => "pilot_analysis_failed"}]
            }} = Task.await(task, 2_000)

    assert_receive {:failure_persistence, @failure_persistence_event, %{}, metadata}, 1_000

    assert metadata == %{
             execution_id: context.execution.id,
             active_phase: :pilot_analysis,
             failure: :persistence_failed
           }

    refute_receive {:failure_persistence, @failure_persistence_event, _, _}, 50
    assert Repo.get!(StudyExecution, context.execution.id).state == :analyzing_pilot
  end

  test "STUDY-COORD-05: cancellation wins the locked transition race", context do
    replace_store(context, %{block_collection: true})

    task = Task.async(fn -> run(context.execution.id) end)
    assert_receive {:collection_waiting, coordinator_pid}

    cancel_execution(context.execution)

    send(coordinator_pid, :continue_collection)
    assert Task.await(task, 2_000) == :ok

    execution = Repo.get!(StudyExecution, context.execution.id)
    analysis_phase = pilot_analysis_phase(context.execution)

    assert execution.state == :cancelled
    assert execution.error == nil
    assert execution.pilot_outcome == nil
    assert analysis_phase == nil
    refute_received {:pilot_created, _request}
  end

  test "STUDY-COORD-06: duplicate starts keep one coordinator and one Gust run", context do
    gust_owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(gust_owner) end)

    start_supervised!({DagLoader, %{dags_folder: Application.fetch_env!(:gust, :dags_folder)}})
    _definitions = DagLoader.get_definitions()

    attach_commit_pause()
    Store.put(:pause_commit, :collection)
    run_count = Gust.Repo.aggregate(Gust.Flows.Run, :count)

    assert {:ok, coordinator_pid} = Coordinator.start(context.execution.id)
    coordinator_monitor = Process.monitor(coordinator_pid)
    assert_receive {:run_accepted, :collection, ^coordinator_pid}, 2_000

    assert {:error, %StudyError{code: "conflict"}} = Coordinator.start(context.execution.id)

    assert [{^coordinator_pid, _value}] =
             Registry.lookup(
               NetworkDefense.Evaluation.Study.CoordinatorRegistry,
               context.execution.id
             )

    assert Gust.Repo.aggregate(Gust.Flows.Run, :count) == run_count + 1

    cancel_execution(context.execution)
    send(coordinator_pid, {:continue_after_accept, :collection})
    assert_receive {:DOWN, ^coordinator_monitor, :process, ^coordinator_pid, :normal}, 2_000
    assert Repo.get!(StudyExecution, context.execution.id).state == :cancelled
  end

  test "STUDY-COORD-07: a phase run ID cannot be replaced", context do
    context.pilot_phase
    |> StudyPhase.changeset(%{gust_run_id: 909})
    |> Repo.update!()

    assert {:error, %StudyError{}} = run(context.execution.id)

    phase = Repo.get!(StudyPhase, context.pilot_phase.id)
    assert phase.gust_run_id == 909
    refute_received {:collection_dispatched, _pid}
  end

  test "STUDY-COORD-08: cancellation committed before collection dispatch prevents dispatch",
       context do
    attach_commit_pause()
    Store.put(:pause_commit, :collection)

    task = Task.async(fn -> run(context.execution.id) end)
    assert_receive {:run_accepted, :collection, coordinator_pid}, 1_000
    assert Repo.get!(StudyPhase, context.pilot_phase.id).gust_run_id == 101

    cancel_execution(context.execution)
    send(coordinator_pid, {:continue_after_accept, :collection})

    assert Task.await(task, 2_000) == :ok
    assert Repo.get!(StudyExecution, context.execution.id).state == :cancelled
    refute_received {:collection_dispatched, _pid}
  end

  test "STUDY-COORD-09: cancellation committed before analysis dispatch prevents dispatch",
       context do
    attach_commit_pause()
    replace_store(context, %{pause_analysis_accept: true})

    task = Task.async(fn -> run(context.execution.id) end)
    assert_receive {:run_accepted, :analysis, coordinator_pid}, 2_000
    assert pilot_analysis_phase(context.execution).gust_run_id == 202

    cancel_execution(context.execution)
    send(coordinator_pid, {:continue_after_accept, :analysis})

    assert Task.await(task, 2_000) == :ok
    assert Repo.get!(StudyExecution, context.execution.id).state == :cancelled
    refute_received {:pilot_dispatched, _pid}
  end

  test "STUDY-COORD-10: snapshot validation runs before Pilot run creation", context do
    {:ok, mismatched} = PilotConformance.store_snapshot(PilotConformance.snapshot())

    context.pilot_phase
    |> Repo.reload!()
    |> Ecto.Changeset.change(snapshot_id: nil)
    |> Repo.update!()

    assert Repo.get!(StudyPhase, context.pilot_phase.id).snapshot_id == nil
    replace_store(context, %{collection_result: {:ok, mismatched.id}})

    assert {:error, %StudyError{}} = run(context.execution.id)

    execution = Repo.get!(StudyExecution, context.execution.id)
    assert execution.state == :failed
    assert Jason.encode!(execution.error) =~ "pilot_analysis_failed"
    refute_received {:pilot_created, _request}
  end

  test "STUDY-COORD-12: WHEN the Pilot collection snapshot is accepted, THE coordinator SHALL create one pilot_analysis phase in that transition and SHALL continue into Pilot analysis",
       context do
    assert pilot_analysis_phase(context.execution) == nil

    assert :ok = run(context.execution.id)

    phase = pilot_analysis_phase(context.execution)
    assert phase.phase == :pilot_analysis
    assert phase.gust_run_id == 202

    assert Repo.all(
             from(row in StudyPhase,
               where: row.execution_id == ^context.execution.id,
               select: row.phase,
               order_by: row.phase
             )
           ) == [:final_collection, :pilot_analysis, :pilot_collection]

    assert Repo.get!(StudyExecution, context.execution.id).state == :awaiting_final
  end

  test "STUDY-COORD-13: WHEN the Pilot analysis phase cannot be created, THE coordinator SHALL keep the bounded Pilot workflow error on the Pilot collection phase and SHALL leave no accepted handoff behind",
       context do
    conflicting = StudyFixtures.insert_phase(context.execution, :pilot_analysis)

    # The setup assembles the Pilot snapshot and links it to the collection
    # phase. Clear that link on the stored row, so the handoff below is the only
    # writer of the snapshot and its rollback stays observable.
    _cleared =
      StudyPhase
      |> Repo.get!(context.pilot_phase.id)
      |> StudyPhase.changeset(%{snapshot_id: nil})
      |> Repo.update!()

    assert {:error,
            %StudyError{
              code: "unavailable",
              issues: [%{"code" => "pilot_analysis_failed"}]
            }} = run(context.execution.id)

    execution = Repo.get!(StudyExecution, context.execution.id)
    assert execution.state == :failed
    assert Jason.encode!(execution.error) =~ "pilot_analysis_failed"

    collection_phase = Repo.get!(StudyPhase, context.pilot_phase.id)
    assert collection_phase.snapshot_id == nil
    assert collection_phase.error == StudyError.to_params(StudyError.pilot_analysis_failed())

    unchanged = Repo.get!(StudyPhase, conflicting.id)
    assert unchanged.gust_run_id == nil
    assert unchanged.snapshot_id == nil
    assert unchanged.result_ref == nil
    assert unchanged.error == nil

    refute_received {:pilot_created, _request}
    refute_received {:pilot_dispatched, _pid}
  end

  defp pilot_analysis_phase(execution) do
    Repo.get_by(StudyPhase, execution_id: execution.id, phase: :pilot_analysis)
  end

  defp run(execution_id) do
    Coordinator.run(execution_id, coordinator_opts())
  end

  defp coordinator_opts do
    [collection_workflow: CollectionWorkflowStub, pilot_workflow: PilotWorkflowStub]
  end

  defp replace_store(context, changes) do
    Agent.update(Store, fn state ->
      state
      |> Map.merge(changes)
      |> Map.put(
        :collection_result,
        Map.get(changes, :collection_result, {:ok, context.snapshot.id})
      )
    end)
  end

  defp cancel_execution(execution) do
    execution
    |> Repo.reload!()
    |> StudyExecution.changeset(%{state: :cancelled})
    |> Repo.update!()
  end

  defp attach_commit_pause do
    owner = self()
    handler_id = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler_id,
        [:network_defense, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          pause_commit(metadata, owner)
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp pause_commit(metadata, owner) do
    query = metadata.query |> IO.iodata_to_binary() |> String.downcase()

    if query == "commit", do: await_commit_release(owner)
  end

  defp await_commit_release(owner) do
    case Store.take(:pause_commit) do
      nil ->
        :ok

      stage ->
        send(owner, {:run_accepted, stage, self()})

        receive do
          {:continue_after_accept, ^stage} -> :ok
        end
    end
  end
end
