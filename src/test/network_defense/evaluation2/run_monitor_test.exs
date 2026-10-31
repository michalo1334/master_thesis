defmodule NetworkDefense.Evaluation2.RunMonitorTest do
  use NetworkDefense.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.Flows.{Dag, Run}
  alias Gust.Repo, as: GustRepo
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Persistence.Execution
  alias NetworkDefense.Evaluation2.Study.Persistence.Revision
  alias NetworkDefense.Evaluation2.Study.Workflow.RunMonitor

  @moduletag :integration
  @moduletag case_id: "FLOW-03/FLOW-04"

  @poll_bound_ms 5_000

  setup do
    gust_owner = Sandbox.start_owner!(GustRepo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(gust_owner) end)
    :ok
  end

  test "WHEN the linked Gust run already succeeded THEN the wait reports the terminal run" do
    run = insert_run(:succeeded)
    execution = insert_execution(:collecting_pilot)

    assert {:ok, :terminal} = RunMonitor.await(run.id, execution.id)
  end

  test "WHEN the linked Gust run failed THEN the wait reports the terminal run" do
    run = insert_run(:failed)
    execution = insert_execution(:collecting_pilot)

    assert {:ok, :terminal} = RunMonitor.await(run.id, execution.id)
  end

  test "WHEN the run and the execution stay active THEN a finite bound returns :timeout without changing work" do
    run = insert_run(:enqueued)
    execution = insert_execution(:collecting_pilot)

    assert :timeout = RunMonitor.await(run.id, execution.id, 250)

    assert GustRepo.get!(Run, run.id).status == :enqueued
    assert Repo.get!(Execution, execution.id).state == :collecting_pilot
  end

  test "WHEN another process cancels the durable execution THEN a waiting caller observes it" do
    run = insert_run(:running)
    execution = insert_execution(:collecting_pilot)

    canceller = spawn_updater(fn -> cancel_execution(execution) end)

    assert {:ok, :cancelled} = RunMonitor.await(run.id, execution.id, @poll_bound_ms)
    assert_receive {:updated, ^canceller}, @poll_bound_ms
    assert Repo.get!(Execution, execution.id).state == :cancelled
  end

  test "WHEN another process completes the linked run THEN a waiting caller observes the terminal status" do
    run = insert_run(:running)
    execution = insert_execution(:collecting_pilot)

    completer = spawn_updater(fn -> update_run_status(run, :succeeded) end)

    assert {:ok, :terminal} = RunMonitor.await(run.id, execution.id, @poll_bound_ms)
    assert_receive {:updated, ^completer}, @poll_bound_ms
  end

  test "WHEN a cancelled execution receives a late valid run THEN the durable cancellation wins" do
    run = insert_run(:succeeded)
    execution = insert_execution(:cancelled)

    assert {:ok, :cancelled} = RunMonitor.await(run.id, execution.id)
  end

  test "WHEN the durable execution failed THEN the wait reports the fenced execution" do
    run = insert_run(:running)
    execution = insert_execution(:failed)

    assert {:ok, :cancelled} = RunMonitor.await(run.id, execution.id)
  end

  test "WHEN a linked record is missing THEN the wait reports one bounded error" do
    execution = insert_execution(:collecting_pilot)
    run = insert_run(:enqueued)

    assert {:error, %Error{category: :unavailable, issues: [%{code: "run_not_found"}]}} =
             RunMonitor.await(run.id + 1_000_000_000, execution.id)

    assert {:error,
            %Error{category: :validation_failed, issues: [%{code: "execution_not_found"}]}} =
             RunMonitor.await(run.id, Ecto.UUID.generate())

    assert {:error,
            %Error{category: :validation_failed, issues: [%{code: "execution_not_found"}]}} =
             RunMonitor.await(run.id, "not-an-execution-identity")
  end

  test "WHEN the durable execution already succeeded THEN the wait reports the terminal state" do
    run = insert_run(:running)
    execution = insert_execution(:succeeded)

    assert {:ok, :terminal} = RunMonitor.await(run.id, execution.id)
  end

  test "WHEN the execution waits at the approval gate THEN the wait keeps waiting" do
    run = insert_run(:enqueued)
    execution = insert_execution(:awaiting_final)

    assert :timeout = RunMonitor.await(run.id, execution.id, 250)
  end

  test "WHEN the waiting caller exits THEN the monitor removes the wait" do
    run = insert_run(:enqueued)
    execution = insert_execution(:collecting_pilot)
    key = {run.id, execution.id}

    caller = spawn_caller(key, :infinity)
    eventually(fn -> cited?(key) end)

    Process.exit(caller, :kill)
    eventually(fn -> not cited?(key) end)

    update_execution_state(execution, :cancelled)
    assert {:ok, :cancelled} = RunMonitor.await(run.id, execution.id)
  end

  test "WHEN two callers wait on one run THEN each elapsed bound applies to its own caller" do
    run = insert_run(:running)
    execution = insert_execution(:collecting_pilot)

    blocking = spawn_caller({run.id, execution.id}, :infinity)

    assert :timeout = RunMonitor.await(run.id, execution.id, 250)
    assert cited?({run.id, execution.id})

    cancel_execution(execution)
    assert_receive {:awaited, ^blocking, {:ok, :cancelled}}, @poll_bound_ms
  end

  defp insert_run(status) do
    dag =
      GustRepo.insert!(%Dag{
        name: "run_monitor_#{System.unique_integer([:positive])}"
      })

    GustRepo.insert!(%Run{dag_id: dag.id, status: status})
  end

  defp insert_execution(state) do
    revision =
      Repo.insert!(%Revision{
        study_id: "run-monitor-#{System.unique_integer([:positive])}",
        revision: 1,
        definition: %{}
      })

    execution = %Execution{study_revision_id: revision.id, state: state}
    Repo.insert!(declared_values(execution, state))
  end

  # A declared state owns declared companions: a failed execution owns one bounded
  # error, the approval gate owns the Pilot outcome, and a succeeded execution owns
  # the outcome and the frozen selection.
  defp declared_values(execution, :failed) do
    %{execution | error: %{"category" => "unavailable", "issues" => []}}
  end

  defp declared_values(execution, :awaiting_final), do: %{execution | pilot_outcome: %{}}

  defp declared_values(execution, :succeeded),
    do: %{execution | pilot_outcome: %{}, selection: %{}}

  defp declared_values(execution, _state), do: execution

  defp cancel_execution(execution), do: update_execution_state(execution, :cancelled)

  defp update_execution_state(execution, state) do
    Execution
    |> Repo.get!(execution.id)
    |> Ecto.Changeset.change(state: state)
    |> Repo.update!()
  end

  defp update_run_status(run, status) do
    Run
    |> GustRepo.get!(run.id)
    |> Ecto.Changeset.change(status: status)
    |> GustRepo.update!()
  end

  # A separate process stands in for the other command VM that commits the durable
  # change, so the waiting caller cannot rely on a local notification.
  defp spawn_updater(fun) do
    test = self()

    spawn(fn ->
      Process.sleep(150)
      fun.()
      send(test, {:updated, self()})
    end)
  end

  defp spawn_caller(key, timeout) do
    {gust_run_id, execution_id} = key
    test = self()

    spawn(fn ->
      send(test, {:awaited, self(), RunMonitor.await(gust_run_id, execution_id, timeout)})
    end)
  end

  defp cited?(key) do
    RunMonitor
    |> :sys.get_state()
    |> Map.fetch!(:waits)
    |> Map.has_key?(key)
  end

  defp eventually(fun, attempts \\ 100)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(20)
      eventually(fun, attempts - 1)
    end
  end

  defp eventually(_fun, 0), do: flunk("The condition did not hold within the bounded check.")
end
