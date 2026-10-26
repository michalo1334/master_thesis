defmodule NetworkDefense.Evaluation.Study.StudyCollectionConcurrencyGateTest do
  use ExUnit.Case, async: false

  alias NetworkDefense.Evaluation.Study.{CollectionConcurrencyGate, CollectionLimits}
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError

  setup do
    original = Application.get_env(:network_defense, CollectionLimits)

    Application.put_env(:network_defense, CollectionLimits,
      max_phase_items: 24,
      max_gust_concurrency: 2
    )

    on_exit(fn ->
      ensure_limiter_started()
      Application.put_env(:network_defense, CollectionLimits, original)
    end)
  end

  test "STUDY-COLLECTION-01: mapped collection work does not exceed the local Gust limit" do
    parent = self()

    tasks =
      for index <- 1..4 do
        Task.async(fn ->
          CollectionConcurrencyGate.run(fn ->
            send(parent, {:entered, index, self()})

            receive do
              :release -> :ok
            end
          end)
        end)
      end

    first = receive_entered()
    second = receive_entered()
    assert_limiter_state(2, 2)

    send(elem(first, 1), :release)
    third = receive_entered()
    assert_limiter_state(2, 1)

    for {_index, pid} <- [second, third], do: send(pid, :release)
    fourth = receive_entered()
    send(elem(fourth, 1), :release)

    assert Enum.map(tasks, &Task.await(&1, 1_000)) == [:ok, :ok, :ok, :ok]
  end

  test "STUDY-COLLECTION-06: holder death releases capacity" do
    set_limit(1)
    parent = self()

    holder =
      spawn(fn ->
        CollectionConcurrencyGate.run(fn ->
          send(parent, {:holder_entered, self()})
          receive(do: (:hold -> :ok))
        end)
      end)

    holder_monitor = Process.monitor(holder)
    assert_receive {:holder_entered, ^holder}, 1_000

    next = run_blocked(parent, :next_entered)
    assert_limiter_state(1, 1)

    Process.exit(holder, :kill)
    assert_receive {:DOWN, ^holder_monitor, :process, ^holder, :killed}, 1_000
    assert_receive {:next_entered, next_pid}, 1_000

    send(next_pid, :release)
    assert Task.await(next, 1_000) == :ok
  end

  test "STUDY-COLLECTION-07: queued caller death removes its waiter" do
    set_limit(1)
    parent = self()
    holder = run_blocked(parent, :holder_entered)
    assert_receive {:holder_entered, holder_pid}, 1_000

    queued =
      spawn(fn ->
        send(parent, {:queued, self()})
        CollectionConcurrencyGate.run(fn -> send(parent, :dead_caller_entered) end)
      end)

    queued_monitor = Process.monitor(queued)
    assert_receive {:queued, ^queued}, 1_000
    assert_limiter_state(1, 1)

    Process.exit(queued, :kill)
    assert_receive {:DOWN, ^queued_monitor, :process, ^queued, :killed}, 1_000
    assert_limiter_state(1, 0)

    send(holder_pid, :release)
    assert Task.await(holder, 1_000) == :ok
    refute_received :dead_caller_entered
  end

  test "STUDY-COLLECTION-08: a gate crash keeps new work bounded until manual restart" do
    set_limit(1)
    parent = self()
    holder = run_blocked(parent, :holder_entered)
    assert_receive {:holder_entered, holder_pid}, 1_000

    queued =
      Task.async(fn ->
        CollectionConcurrencyGate.run(fn -> send(parent, :unexpected_entry) end)
      end)

    assert_limiter_state(1, 1)

    gate = Process.whereis(CollectionConcurrencyGate)
    gate_monitor = Process.monitor(gate)
    Process.exit(gate, :kill)

    assert_receive {:DOWN, ^gate_monitor, :process, ^gate, :killed}, 1_000
    assert Process.whereis(CollectionConcurrencyGate) == nil
    assert {:error, %StudyError{code: "unavailable"}} = Task.await(queued, 1_000)

    assert {:error, %StudyError{code: "unavailable"}} =
             CollectionConcurrencyGate.run(fn -> send(parent, :unexpected_entry) end)

    refute_received :unexpected_entry

    send(holder_pid, :release)
    assert Task.await(holder, 1_000) == :ok
    assert Process.whereis(CollectionConcurrencyGate) == nil

    ensure_limiter_started()
    assert CollectionConcurrencyGate.run(fn -> :restarted end) == :restarted
  end

  defp run_blocked(parent, entered) do
    Task.async(fn ->
      CollectionConcurrencyGate.run(fn ->
        send(parent, {entered, self()})
        receive(do: (:release -> :ok))
      end)
    end)
  end

  defp receive_entered do
    assert_receive {:entered, index, pid}, 1_000
    {index, pid}
  end

  defp assert_limiter_state(holder_count, waiter_count) do
    wait_for(fn ->
      state = :sys.get_state(CollectionConcurrencyGate)
      map_size(state.holders) == holder_count and length(state.waiters) == waiter_count
    end)
  end

  defp wait_for(predicate, attempts \\ 10_000)
  defp wait_for(_predicate, 0), do: flunk("the limiter did not reach the expected state")

  defp wait_for(predicate, attempts) do
    if predicate.() do
      :ok
    else
      Process.sleep(0)
      wait_for(predicate, attempts - 1)
    end
  end

  defp set_limit(limit) do
    Application.put_env(:network_defense, CollectionLimits,
      max_phase_items: 24,
      max_gust_concurrency: limit
    )
  end

  defp ensure_limiter_started do
    if Process.whereis(CollectionConcurrencyGate) == nil do
      child_spec = CollectionConcurrencyGate.child_spec([])

      assert {:ok, _pid} = Supervisor.start_child(NetworkDefense.Supervisor, child_spec)
    end
  end
end
