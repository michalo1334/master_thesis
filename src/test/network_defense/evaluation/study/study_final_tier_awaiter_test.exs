defmodule NetworkDefense.Evaluation.Study.FinalTierAwaiterTest do
  use NetworkDefense.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.Flows.Run
  alias NetworkDefense.Evaluation.Study.Actions.MarkFinalTimingBoundary

  alias NetworkDefense.Evaluation.Study.{
    Cancel,
    FinalTierAwaiter,
    GustRunNotifier,
    GustWaiter,
    PhaseRuns
  }

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Timing.Recorder
  alias NetworkDefense.Evaluation.{StudyExecution, StudyFixtures}

  @registry NetworkDefense.Evaluation.Study.CoordinatorRegistry
  @events [:plan_dispatch, :plan_completion, :simulation_dispatch, :simulation_completion]

  setup do
    owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    study = StudyFixtures.study_with_two_phases()
    {:ok, phase_run} = PhaseRuns.get_or_create(study.final_phase, "core", 0)
    {:ok, dag} = Gust.Flows.create_dag(%{name: "final_tier_awaiter_test"})
    {:ok, run} = Gust.Flows.create_run(%{dag_id: dag.id})
    {:ok, phase_run} = PhaseRuns.link_gust_run(phase_run, run.id)
    Map.merge(study, %{phase_run: phase_run, run: run})
  end

  test "CHUNK-B-AWAIT-01: WHEN Gust succeeds after all markers, THE awaiter SHALL return five timings",
       context do
    waiter = start_wait(context)

    for position <- 0..4,
        event <- @events,
        do: assert(marker(waiter, context, position, event) == :ok)

    # A duplicate remains valid even after later boundaries.
    assert marker(waiter, context, 0, :plan_dispatch) == :ok
    finish(context.run, :succeeded)
    assert {:ok, timings} = Task.await(waiter)
    assert Enum.map(timings, & &1.position) == Enum.to_list(0..4)
    assert Enum.all?(timings, &(&1.tier == "core"))
  end

  test "CHUNK-B-AWAIT-02: WHEN Gust succeeds with missing boundaries, THE awaiter SHALL reject incomplete timing",
       context do
    waiter = start_wait(context)
    assert marker(waiter, context, 0, :plan_dispatch) == :ok
    finish(context.run, :succeeded)
    assert Task.await(waiter) == {:error, StudyError.final_timing_incomplete()}
  end

  test "CHUNK-B-AWAIT-03: WHEN a marker is invalid, THE awaiter SHALL reject it and queued later markers",
       context do
    block_gust_waiter()
    # Queue both before entering the receive loop to make terminal draining deterministic.
    first = make_ref()
    second = make_ref()

    send(
      self(),
      {:final_timing_boundary, first, context.execution.id, context.phase_run.id, 0,
       :plan_completion, self()}
    )

    send(
      self(),
      {:final_timing_boundary, second, context.execution.id, context.phase_run.id, 0,
       :plan_dispatch, self()}
    )

    assert FinalTierAwaiter.await(context.execution, context.phase_run, 1_000) ==
             {:error, StudyError.final_timing_invalid()}

    assert_received {:final_timing_boundary_ack, ^first, {:error, %StudyError{}}}
    assert_received {:final_timing_boundary_ack, ^second, {:error, %StudyError{}}}
    refute_received {:final_tier_gust_result, _reference, _result}
  end

  test "CHUNK-B-AWAIT-04: WHEN Gust fails, THE awaiter SHALL return a bounded workflow failure",
       context do
    finish(context.run, :failed)

    assert FinalTierAwaiter.await(context.execution, context.phase_run, 1_000) ==
             {:error, StudyError.final_collection_workflow_failed()}
  end

  test "CHUNK-B-AWAIT-05: WHEN duplicate traffic continues, THE absolute deadline SHALL still stop the awaiter",
       context do
    waiter = start_wait(context, 100)
    sender = Task.async(fn -> duplicate_traffic(waiter, context) end)
    assert Task.await(waiter, 1_000) == {:error, StudyError.final_timing_unavailable()}
    Task.shutdown(sender, :brutal_kill)
  end

  test "CHUNK-B-AWAIT-06: WHEN cancellation wakes the awaiter, THE stored state SHALL control cancellation",
       context do
    waiter = start_wait(context)
    send(waiter.pid, {:study_cancelled, context.execution.id})
    assert marker(waiter, context, 0, :plan_dispatch) == :ok
    assert {:ok, %StudyExecution{state: :cancelled}} = Cancel.cancel(context.execution.id)
    assert Task.await(waiter) == {:error, StudyError.final_collection_workflow_failed()}
    assert Repo.get!(StudyExecution, context.execution.id).state == :cancelled
  end

  test "CHUNK-B-AWAIT-07: WHEN cancellation precedes queued markers, THE awaiter SHALL reject late markers",
       context do
    block_gust_waiter()
    assert {:ok, _cancelled} = Cancel.cancel(context.execution.id)
    ref = make_ref()
    send(self(), {:study_cancelled, context.execution.id})

    send(
      self(),
      {:final_timing_boundary, ref, context.execution.id, context.phase_run.id, 0, :plan_dispatch,
       self()}
    )

    assert {:error, %StudyError{}} =
             FinalTierAwaiter.await(context.execution, context.phase_run, 1_000)

    assert_received {:final_timing_boundary_ack, ^ref, {:error, %StudyError{}}}
  end

  test "CHUNK-B-MARKER-01: WHEN a marker waits for acknowledgement, THE action SHALL not finish before the receiver records it",
       context do
    {:ok, _owner} = Registry.register(@registry, context.execution.id, nil)
    action = Task.async(fn -> MarkFinalTimingBoundary.execute(marker_args(context), %{}) end)

    assert_receive {:final_timing_boundary, ref, execution_id, phase_run_id, 0, :plan_dispatch,
                    marker_pid}

    assert execution_id == context.execution.id
    assert phase_run_id == context.phase_run.id
    assert Task.yield(action, 0) == nil
    {:ok, recorder} = Recorder.record(Recorder.new("core"), "core", 0, :plan_dispatch)
    assert map_size(recorder.readings) == 1
    send(marker_pid, {:final_timing_boundary_ack, make_ref(), :ok})
    assert Task.yield(action, 0) == nil
    send(marker_pid, {:final_timing_boundary_ack, ref, :ok})
    assert %{"replica_position" => 0} = Task.await(action)
    Registry.unregister(@registry, context.execution.id)
  end

  test "CHUNK-B-MARKER-02: WHEN the coordinator is absent or does not acknowledge, THE action SHALL fail permanently",
       context do
    assert_raise Gust.DAG.NonRecError, ~r/final_timing_unavailable/, fn ->
      MarkFinalTimingBoundary.execute(marker_args(context), %{})
    end

    parent = self()

    coordinator =
      spawn(fn ->
        Registry.register(@registry, context.execution.id, nil)
        send(parent, :registered)

        receive do
          :stop -> :ok
        end
      end)

    assert_receive :registered
    on_exit(fn -> Process.exit(coordinator, :kill) end)

    assert_raise Gust.DAG.NonRecError, ~r/final_timing_unavailable/, fn ->
      MarkFinalTimingBoundary.execute(marker_args(context), %{})
    end
  end

  @tag type: :integration, case_id: "CHUNK-B-MARKER-03"
  test "CHUNK-B-MARKER-03: WHEN event kinds use atoms or strings, THE action SHALL send the same bounded event",
       context do
    parent = self()

    coordinator =
      Task.async(fn ->
        {:ok, _owner} = Registry.register(@registry, context.execution.id, nil)
        send(parent, {:normalization_ready, self()})

        for _input <- 1..8 do
          receive do
            {:final_timing_boundary, ref, execution_id, phase_run_id, 0, event, marker_pid} ->
              send(parent, {:normalized_event, execution_id, phase_run_id, event})
              send(marker_pid, {:final_timing_boundary_ack, ref, :ok})
          end
        end

        :ok
      end)

    on_exit(fn ->
      if Process.alive?(coordinator.pid), do: Process.exit(coordinator.pid, :kill)
    end)

    assert_receive {:normalization_ready, pid}
    assert pid == coordinator.pid

    for event <- @events, input <- [event, Atom.to_string(event)] do
      args = Keyword.put(marker_args(context), :event_kind, input)

      assert %{"study_phase_run_id" => id, "replica_position" => 0} =
               MarkFinalTimingBoundary.execute(args, %{})

      assert id == context.phase_run.id
      assert_received {:normalized_event, execution_id, phase_run_id, ^event}
      assert execution_id == context.execution.id
      assert phase_run_id == context.phase_run.id
    end

    assert Task.await(coordinator) == :ok
  end

  @tag type: :integration, case_id: "CHUNK-B-MARKER-04"
  test "CHUNK-B-MARKER-04: WHEN an event kind is unknown, THE action SHALL reject it permanently",
       context do
    for event <- [:unknown, "unknown", "PLAN_DISPATCH", nil] do
      error =
        assert_raise Gust.DAG.NonRecError, fn ->
          MarkFinalTimingBoundary.execute(
            Keyword.put(marker_args(context), :event_kind, event),
            %{}
          )
        end

      assert Jason.decode!(error.message)["error"] ==
               StudyError.to_params(StudyError.final_timing_invalid())
    end
  end

  test "CHUNK-B-AWAIT-08: WHEN the stored phase-run identity differs, THE awaiter SHALL reject timing",
       context do
    for phase_run <- [
          %{context.phase_run | tier: "other"},
          %{context.phase_run | id: Ecto.UUID.generate()}
        ] do
      assert FinalTierAwaiter.await(context.execution, phase_run, 100) ==
               {:error, StudyError.final_timing_invalid()}
    end

    assert FinalTierAwaiter.await(
             %{context.execution | id: Ecto.UUID.generate()},
             context.phase_run,
             100
           ) == {:error, StudyError.final_timing_invalid()}

    assert FinalTierAwaiter.await(context.execution, %{context.phase_run | gust_run_id: nil}, 100) ==
             {:error, StudyError.final_timing_unavailable()}
  end

  test "CHUNK-B-AWAIT-09: WHEN the Gust helper is unavailable or crashes, THE awaiter SHALL stop with a bounded error",
       context do
    :meck.new(GustWaiter, [:passthrough, :no_link])
    on_exit(fn -> :meck.unload(GustWaiter) end)

    for reason <- [:unavailable, :timeout] do
      :meck.expect(GustWaiter, :await, fn _run_id, _timeout -> {:error, reason} end)

      assert FinalTierAwaiter.await(context.execution, context.phase_run, 1_000) ==
               {:error, StudyError.final_timing_unavailable()}
    end

    :meck.expect(GustWaiter, :await, fn _run_id, _timeout -> exit(:test_helper_crash) end)

    assert FinalTierAwaiter.await(context.execution, context.phase_run, 1_000) ==
             {:error, StudyError.final_timing_unavailable()}

    refute_received {:final_tier_gust_result, _reference, _result}
    refute_received {:DOWN, _monitor, :process, _pid, _reason}
  end

  test "CHUNK-B-AWAIT-10: WHEN timing fails, THE awaiter SHALL stop its monitored helper",
       context do
    block_gust_waiter()
    waiter = start_wait(context)
    assert_receive {:gust_helper_started, helper}
    monitor = Process.monitor(helper)
    assert {:error, %StudyError{}} = marker(waiter, context, 0, :simulation_completion)
    assert Task.await(waiter) == {:error, StudyError.final_timing_invalid()}
    assert_receive {:DOWN, ^monitor, :process, ^helper, _reason}
  end

  test "CHUNK-B-AWAIT-11: WHEN cancellation storage is unavailable, THE awaiter SHALL stop its helper and return a bounded error",
       context do
    block_gust_waiter()
    :meck.new(Repo, [:passthrough, :no_link])
    on_exit(fn -> :meck.unload(Repo) end)

    :meck.expect(Repo, :get, fn
      StudyExecution, _id ->
        raise DBConnection.ConnectionError, message: "private database diagnostic"

      schema, id ->
        :meck.passthrough([schema, id])
    end)

    waiter = start_wait(context)
    assert_receive {:gust_helper_started, helper}
    on_exit(fn -> if Process.alive?(helper), do: Process.exit(helper, :kill) end)
    monitor = Process.monitor(helper)
    send(waiter.pid, {:study_cancelled, context.execution.id})
    assert Task.await(waiter) == {:error, StudyError.study_execution_storage_failed()}
    assert_receive {:DOWN, ^monitor, :process, ^helper, _reason}
  end

  defp block_gust_waiter do
    parent = self()
    :meck.new(GustWaiter, [:passthrough, :no_link])
    on_exit(fn -> :meck.unload(GustWaiter) end)

    :meck.expect(GustWaiter, :await, fn _run_id, _timeout ->
      send(parent, {:gust_helper_started, self()})

      receive do
        :finish -> {:ok, :succeeded}
      end
    end)
  end

  defp marker_args(context),
    do: [
      study_phase_run_id: context.phase_run.id,
      replica_position: 0,
      event_kind: :plan_dispatch
    ]

  defp start_wait(context, timeout \\ 5_000) do
    parent = self()

    task =
      Task.async(fn ->
        {:ok, _owner} = Registry.register(@registry, context.execution.id, nil)
        send(parent, {:ready, self()})
        FinalTierAwaiter.await(context.execution, context.phase_run, timeout)
      end)

    assert_receive {:ready, pid}
    assert pid == task.pid
    task
  end

  defp marker(waiter, context, position, event) do
    ref = make_ref()

    send(
      waiter.pid,
      {:final_timing_boundary, ref, context.execution.id, context.phase_run.id, position, event,
       self()}
    )

    assert_receive {:final_timing_boundary_ack, ^ref, result}, 1_000
    result
  end

  defp finish(run, status) do
    run |> Run.changeset(%{status: status}) |> Gust.Repo.update!()
    GustRunNotifier.notify(run.id)
  end

  defp duplicate_traffic(waiter, context) do
    if Process.alive?(waiter.pid) do
      ref = make_ref()

      send(
        waiter.pid,
        {:final_timing_boundary, ref, context.execution.id, context.phase_run.id, 0,
         :plan_dispatch, self()}
      )

      receive do
        {:final_timing_boundary_ack, ^ref, :ok} -> duplicate_traffic(waiter, context)
      end
    end
  end
end
