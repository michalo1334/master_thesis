defmodule NetworkDefense.Evaluation.Study.StudyGustWaiterTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias NetworkDefense.Evaluation.Final.Contracts.FinalError
  alias NetworkDefense.Evaluation.Final.Workflow, as: FinalWorkflow
  alias NetworkDefense.Evaluation.Pilot.Contracts.PilotError
  alias NetworkDefense.Evaluation.Pilot.Workflow

  alias NetworkDefense.Evaluation.Study.{
    CollectionWorkflow,
    FinalTierWorkflow,
    GustRunNotifier,
    GustWaiter
  }

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError

  @waiter_registry NetworkDefense.Evaluation.Study.GustWaiterRegistry

  setup do
    gust_owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(gust_owner) end)

    {:ok, dag} =
      Gust.Flows.create_dag(%{name: "study_waiter_#{System.unique_integer([:positive])}"})

    %{dag: dag}
  end

  test "STUDY-WAITER-01: two callers can wait for the same run", %{dag: dag} do
    run = create_run(dag)
    first = Task.async(fn -> GustWaiter.await(run.id, 1_000) end)
    second = Task.async(fn -> GustWaiter.await(run.id, 1_000) end)

    assert [_, _] = waiter_entries(run.id, 2)

    update_status(run.id, :succeeded)
    assert :ok = GustRunNotifier.notify(run.id)

    assert Task.await(first, 1_000) == {:ok, :succeeded}
    assert Task.await(second, 1_000) == {:ok, :succeeded}
    assert Registry.lookup(@waiter_registry, run.id) == []
  end

  test "STUDY-WAITER-02: the initial persisted check closes a missed notification race", %{
    dag: dag
  } do
    run = create_run(dag)
    update_status(run.id, :succeeded)

    assert {:ok, :succeeded} = GustWaiter.await(run.id, 1_000)
    assert Registry.lookup(@waiter_registry, run.id) == []
  end

  test "STUDY-WAITER-03: notifications reload the row and only persisted terminal state completes",
       %{dag: dag} do
    run = create_run(dag)
    waiter = Task.async(fn -> GustWaiter.await(run.id, 1_000) end)

    assert [_entry] = waiter_entries(run.id, 1)
    assert :ok = GustRunNotifier.notify(run.id)
    assert Task.yield(waiter, 50) == nil

    update_status(run.id, :succeeded)
    assert Task.yield(waiter, 50) == nil

    assert :ok = GustRunNotifier.notify(run.id)
    assert Task.await(waiter, 1_000) == {:ok, :succeeded}
  end

  test "STUDY-WAITER-04: nonterminal notifications do not reset the total deadline", %{
    dag: dag
  } do
    run = create_run(dag)
    owner = self()

    notifier =
      spawn(fn ->
        Enum.each(1..30, fn _index ->
          Process.sleep(10)
          GustRunNotifier.notify(run.id)
        end)

        send(owner, :notifications_finished)
      end)

    marker = Process.send_after(self(), :past_total_deadline, 250)

    try do
      assert {:error, :timeout} = GustWaiter.await(run.id, 100)
      refute_received :past_total_deadline
      assert Registry.lookup(@waiter_registry, run.id) == []
    after
      Process.cancel_timer(marker)
      Process.exit(notifier, :kill)
    end
  end

  test "STUDY-WAITER-05: caller exit stops its temporary waiter and removes registration", %{
    dag: dag
  } do
    run = create_run(dag)
    owner = self()

    caller =
      spawn(fn ->
        send(owner, {:caller_started, self()})
        _result = GustWaiter.await(run.id, :infinity)
        send(owner, :unexpected_wait_result)
      end)

    assert_receive {:caller_started, ^caller}
    [{waiter, _value}] = waiter_entries(run.id, 1)
    waiter_monitor = Process.monitor(waiter)

    Process.exit(caller, :kill)

    assert_receive {:DOWN, ^waiter_monitor, :process, ^waiter, :normal}, 1_000
    assert Registry.lookup(@waiter_registry, run.id) == []
    refute_received :unexpected_wait_result
  end

  test "STUDY-WAITER-06: timeout removes the temporary waiter registration", %{dag: dag} do
    run = create_run(dag)

    assert {:error, :timeout} = GustWaiter.await(run.id, 20)
    assert Registry.lookup(@waiter_registry, run.id) == []
  end

  test "STUDY-WAITER-07: a late callback cannot affect a later waiter or its caller", %{dag: dag} do
    run = create_run(dag)

    assert {:error, :timeout} = GustWaiter.await(run.id, 20)
    assert :ok = GustRunNotifier.notify(run.id)
    refute_received {:gust_run_finished, _run_id}

    later = Task.async(fn -> GustWaiter.await(run.id, 1_000) end)
    assert [_entry] = waiter_entries(run.id, 1)
    assert Task.yield(later, 50) == nil

    update_status(run.id, :succeeded)
    assert Task.yield(later, 50) == nil

    assert :ok = GustRunNotifier.notify(run.id)
    assert Task.await(later, 1_000) == {:ok, :succeeded}
    refute_received {:gust_run_finished, _run_id}
  end

  test "STUDY-WAITER-08: both DAG callbacks wake waiters through the shared notifier", %{
    dag: dag
  } do
    modules = compile_dag_modules()

    for module <- modules do
      assert module.__dag_options__()[:on_finished_callback] == :notify_waiters

      run = create_run(dag)
      waiter = Task.async(fn -> GustWaiter.await(run.id, 1_000) end)
      assert [_entry] = waiter_entries(run.id, 1)

      update_status(run.id, :succeeded)
      assert :ok = module.notify_waiters(:untrusted_status, %{id: run.id, status: :stale})
      assert Task.await(waiter, 1_000) == {:ok, :succeeded}
    end
  end

  test "STUDY-WAITER-09: callback failure neither raises nor changes terminal persistence", %{
    dag: dag
  } do
    modules = compile_dag_modules()
    run = create_run(dag)
    update_status(run.id, :failed)

    stop_waiter_registry()

    assert :ok = GustRunNotifier.notify(run.id)

    for module <- modules do
      assert :ok = module.notify_waiters(:succeeded, %{id: run.id, status: :succeeded})
    end

    assert Gust.Flows.get_run!(run.id).status == :failed
  end

  test "STUDY-WAITER-10: waiter-path modules have no PubSub calls" do
    for module <- [
          GustWaiter,
          GustRunNotifier,
          Workflow,
          FinalWorkflow,
          CollectionWorkflow,
          FinalTierWorkflow
        ] do
      imported_modules = imported_modules(module)
      refute Gust.PubSub in imported_modules
      refute Phoenix.PubSub in imported_modules
    end
  end

  test "STUDY-WAITER-11: malformed failed-task diagnostics stay bounded", %{dag: dag} do
    {:ok, run} = Gust.Flows.create_run(%{dag_id: dag.id, params: %{}, status: :failed})

    {:ok, _task} =
      Gust.Flows.create_task(%{
        name: "malformed_failure",
        run_id: run.id,
        status: :failed,
        error: %{"type" => "unknown", "message" => String.duplicate("raw", 1_000)}
      })

    assert {:error, %PilotError{code: "workflow_failed"} = error} = Workflow.await(run.id, 0)
    refute inspect(error) =~ "rawraw"
  end

  test "STUDY-WAITER-12: an unavailable Registry returns a bounded waiter error", %{dag: dag} do
    run = create_run(dag)
    stop_waiter_registry()

    assert {:error, :unavailable} = GustWaiter.await(run.id, 100)
  end

  test "STUDY-WAITER-13: Pilot await maps an unavailable Registry to its workflow error", %{
    dag: dag
  } do
    run = create_run(dag)
    stop_waiter_registry()

    assert Workflow.await(run.id, 100) == {:error, PilotError.workflow_failed()}
  end

  test "STUDY-WAITER-14: collection await maps an unavailable Registry to its workflow error", %{
    dag: dag
  } do
    run = create_run(dag)
    stop_waiter_registry()

    assert CollectionWorkflow.await(run.id, 100) ==
             {:error, StudyError.collection_workflow_failed()}
  end

  test "STUDY-WAITER-15: Final await maps an unavailable Registry to a bounded error", %{
    dag: dag
  } do
    run = create_run(dag)
    stop_waiter_registry()

    assert FinalWorkflow.await(run.id, 100) == {:error, FinalError.unavailable()}
  end

  test "STUDY-WAITER-16: Final tier result maps an unknown run to its bounded error" do
    assert FinalTierWorkflow.result(9_000_000) ==
             {:error, StudyError.final_collection_workflow_failed()}
  end

  defp create_run(dag) do
    {:ok, run} = Gust.Flows.create_run(%{dag_id: dag.id, params: %{}})
    run
  end

  defp update_status(run_id, status) do
    run_id
    |> Gust.Flows.get_run!()
    |> Ecto.Changeset.change(status: status)
    |> Gust.Repo.update!()
  end

  defp waiter_entries(run_id, expected_count, attempts \\ 200)

  defp waiter_entries(run_id, expected_count, attempts) do
    entries = Registry.lookup(@waiter_registry, run_id)

    cond do
      length(entries) == expected_count ->
        entries

      attempts == 0 ->
        flunk("waiter Registry did not reach #{expected_count} entries")

      true ->
        Process.sleep(5)
        waiter_entries(run_id, expected_count, attempts - 1)
    end
  end

  defp stop_waiter_registry do
    assert :ok = Supervisor.terminate_child(NetworkDefense.Supervisor, @waiter_registry)
    assert Process.whereis(@waiter_registry) == nil

    on_exit(fn ->
      case Supervisor.restart_child(NetworkDefense.Supervisor, @waiter_registry) do
        {:ok, _pid} -> :ok
        {:ok, _pid, _info} -> :ok
        {:error, :running} -> :ok
        error -> raise "could not restart Gust waiter Registry: #{inspect(error)}"
      end
    end)
  end

  defp compile_dag_modules do
    root = Path.expand("../../../..", __DIR__)

    modules =
      [
        "priv/gust/dags/evaluation_pilot.exs",
        "priv/gust/dags/evaluation_final.exs",
        "priv/gust/dags/evaluation_study_pilot_collection.exs",
        "priv/gust/dags/evaluation_study_final_tier_collection.exs"
      ]
      |> Enum.flat_map(fn path -> Code.compile_file(Path.join(root, path)) end)
      |> Enum.map(&elem(&1, 0))

    on_exit(fn ->
      Enum.each(modules, fn module ->
        :code.purge(module)
        :code.delete(module)
      end)
    end)

    modules
  end

  defp imported_modules(module) do
    beam_path = :code.which(module)
    {:ok, {_module, [imports: imports]}} = :beam_lib.chunks(beam_path, [:imports])
    imports |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
  end
end
