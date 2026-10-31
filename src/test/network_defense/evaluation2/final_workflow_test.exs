defmodule NetworkDefense.Evaluation2.FinalWorkflowTest do
  use NetworkDefense.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.DAG.Loader.Worker, as: DAGLoader
  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.Final.Timing
  alias NetworkDefense.Evaluation2.Study.{Persistence, Tier, Workflow}
  alias NetworkDefense.Evaluation2Test.FinalFixtures

  @moduletag :integration
  @moduletag case_id: "BIND-01/BIND-02/FLOW-03/FLOW-04/TIME-02/TIME-03"
  @moduletag timeout: 60_000

  setup do
    owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    previous = Application.get_env(:network_defense, :measured_environment_revision)
    Application.put_env(:network_defense, :measured_environment_revision, "final-workflow-test")

    on_exit(fn ->
      Sandbox.stop_owner(owner)

      if previous,
        do: Application.put_env(:network_defense, :measured_environment_revision, previous),
        else: Application.delete_env(:network_defense, :measured_environment_revision)
    end)

    start_supervised!({DAGLoader, %{dags_folder: Application.fetch_env!(:gust, :dags_folder)}})
    DAGLoader.get_definitions()
    %{context: FinalFixtures.approved_context()}
  end

  test "BIND-01 WHEN Final is provisioned repeatedly THEN only its first canonical tier SHALL be dispatched",
       c do
    assert {:ok, first} = Workflow.ensure_next_run(c.context.execution.id)
    assert first.run_key == :small
    assert {:ok, same} = Workflow.ensure_next_run(c.context.execution.id)
    assert same.id == first.id
    assert {:ok, [^first]} = Persistence.list_phase_runs(c.context.active_phase.id)
    assert {:ok, %{state: :collecting_final}} = Study.continue(c.context.execution.id, timeout: 1)
    assert {:ok, [^first]} = Persistence.list_phase_runs(c.context.active_phase.id)
  end

  test "TIME-02/BIND-01 WHEN callers collect Final THEN durable receipts SHALL rebuild after caller and clock loss",
       c do
    parent = self()

    callers =
      for _ <- 1..2 do
        Task.async(fn ->
          send(parent, :started)
          Study.continue(c.context.execution.id)
        end)
      end

    assert_receive :started
    assert_receive :started
    start_supervised!({Gust.Run.DispatcherSupervisor, []})

    for caller <- callers do
      assert {:ok, %{state: :succeeded}} = Task.await(caller, 45_000)
    end

    assert {:ok, %{state: :succeeded}} = Study.status(c.context.execution.id)
    assert {:ok, snapshot} = Persistence.fetch_phase_evidence_snapshot(c.context.active_phase.id)
    assert [_small, _medium, _large] = snapshot.evidence.comparisons

    assert {:ok, successor} =
             Persistence.fetch_execution_phase(c.context.execution.id, :final_analysis)

    assert successor.id != c.context.active_phase.id
    assert {:ok, runs} = Persistence.list_phase_runs(c.context.active_phase.id)
    assert Enum.map(runs, & &1.run_key) == Tier.all()

    before =
      for run <- runs do
        assert {:ok, output} = Workflow.final_tier_result(run.id)
        assert output.tier == run.run_key
        assert Map.keys(output.timing.replicas) |> Enum.sort() == Enum.to_list(0..4)
        {run.id, output}
      end

    assert {:ok, timing} = Workflow.final_timing(c.context.execution.id)
    old = Process.whereis(Timing)
    :ok = Supervisor.terminate_child(NetworkDefense.Supervisor, Timing)
    assert {:ok, _pid} = Supervisor.restart_child(NetworkDefense.Supervisor, Timing)
    refute Process.whereis(Timing) == old
    assert {:ok, ^timing} = Workflow.final_timing(c.context.execution.id)
    for {id, expected} <- before, do: assert({:ok, ^expected} = Workflow.final_tier_result(id))

    assert {:ok, _context} =
             Persistence.Executions.accept_final_collection(c.context.active_phase.id)

    assert {:ok, [^successor]} = final_analysis_phases(c.context.execution.id)
  end

  test "BIND-02 WHEN a successful tier terminal names another tier THEN completion SHALL be rejected",
       c do
    {:ok, run} = completed_small(c)
    [terminal] = Gust.Flows.get_tasks_by_name("complete_final_tier_collection", run.gust_run_id)

    Gust.Repo.update!(
      Ecto.Changeset.change(terminal, result: %{terminal.result | "tier" => "medium"})
    )

    assert {:error, _} = Workflow.final_tier_result(run.id)
    assert {:error, _} = Study.continue(c.context.execution.id, timeout: 500)
    assert {:ok, %{state: :collecting_final}} = Study.status(c.context.execution.id)
    assert {:ok, [^run]} = Persistence.list_phase_runs(c.context.active_phase.id)
  end

  test "FLOW-04 WHEN cancellation precedes valid completed collection THEN no successor SHALL be created",
       c do
    {:ok, _run} = completed_small(c)
    assert {:ok, %{state: :cancelled}} = Study.cancel(c.context.execution.id)
    assert {:ok, %{state: :cancelled}} = Study.continue(c.context.execution.id)

    assert {:error, _} =
             Persistence.fetch_execution_phase(c.context.execution.id, :final_analysis)

    assert {:ok, [_small]} = Persistence.list_phase_runs(c.context.active_phase.id)
  end

  test "TIME-03 WHEN an in-progress measured tier loses its clock THEN it SHALL fail without replacement",
       c do
    alias NetworkDefense.Evaluation2.Study.Collection
    alias NetworkDefense.Evaluation2.Study.Persistence.Collection, as: Store
    parent = self()
    :meck.new(Collection, [:passthrough, :no_link])
    on_exit(fn -> :meck.unload(Collection) end)

    :meck.expect(Collection, :run_optimization, fn item_id ->
      {:ok, item} = Store.fetch_collection_item(item_id)

      if item.replica_position == 0 do
        send(parent, {:measured_item_started, self()})
        receive do: (:allow_effect -> :ok)
      end

      :meck.passthrough([item_id])
    end)

    continuing = Task.async(fn -> Study.continue(c.context.execution.id) end)
    start_supervised!({Gust.Run.DispatcherSupervisor, []})
    assert_receive {:measured_item_started, first}, 10_000
    assert_receive {:measured_item_started, second}, 10_000
    :ok = Supervisor.terminate_child(NetworkDefense.Supervisor, Timing)
    assert {:ok, _pid} = Supervisor.restart_child(NetworkDefense.Supervisor, Timing)
    send(first, :allow_effect)
    send(second, :allow_effect)
    assert {:ok, %{state: :failed}} = Task.await(continuing, 15_000)
    assert {:ok, [run]} = Persistence.list_phase_runs(c.context.active_phase.id)
    assert run.run_key == :small
    assert {:error, _} = Workflow.final_tier_result(run.id)
    assert {:error, _} = Persistence.fetch_phase_evidence_snapshot(c.context.active_phase.id)
    assert {:ok, []} = Store.list_replica_items(run.id, 1)

    assert [] ==
             Gust.Flows.get_tasks_by_name("complete_replica_0", run.gust_run_id)
             |> Enum.filter(&(&1.status == :succeeded))

    assert {:ok, %{state: :failed}} = Study.continue(c.context.execution.id)
    assert {:ok, [^run]} = Persistence.list_phase_runs(c.context.active_phase.id)
  end

  defp completed_small(c) do
    assert {:ok, run} = Workflow.ensure_next_run(c.context.execution.id)
    start_supervised!({Gust.Run.DispatcherSupervisor, []})

    assert {:ok, :terminal} =
             Workflow.RunMonitor.await(run.gust_run_id, c.context.execution.id, 30_000)

    assert {:ok, _output} = Workflow.final_tier_result(run.id)
    {:ok, run}
  end

  defp final_analysis_phases(id) do
    with {:ok, phase} <- Persistence.fetch_execution_phase(id, :final_analysis),
         do: {:ok, [phase]}
  end
end
