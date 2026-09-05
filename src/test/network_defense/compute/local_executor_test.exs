defmodule NetworkDefense.Compute.LocalExecutorTest do
  use ExUnit.Case, async: false

  alias NetworkDefense.Compute.LocalExecutor
  alias NetworkDefense.TestScatterGatherOperation, as: Operation

  test "gathers keyed unordered results after all partitions succeed" do
    input = input([{":a", 2, {:ok, :first}}, {":b", 3, {:ok, :second}}])

    assert {:ok, :done} = LocalExecutor.run(Operation, input, correlation_id: "executor-success")
    assert_received {:gathered, results}
    assert Enum.sort(results) == [{":a", :first}, {":b", :second}]
  end

  test "gathers an empty result list" do
    assert {:ok, :done} =
             LocalExecutor.run(Operation, input([]), correlation_id: "executor-empty")

    assert_received {:gathered, []}
  end

  test "returns partition errors and skips gather" do
    assert {:error, :failed} =
             LocalExecutor.run(Operation, input([{":a", 1, {:error, :failed}}]),
               correlation_id: "executor-error"
             )

    refute_received {:gathered, _results}
  end

  test "returns task exits and skips gather" do
    assert {:error, :stopped} =
             LocalExecutor.run(Operation, input([{":a", 1, {:exit, :stopped}}]),
               correlation_id: "executor-exit"
             )

    refute_received {:gathered, _results}
  end

  test "returns gather errors" do
    assert {:error, :not_saved} =
             LocalExecutor.run(Operation, input([], {:error, :not_saved}),
               correlation_id: "executor-gather"
             )
  end

  test "reports weighted progress" do
    progress = fn update -> send(self(), {:progress, update}) end

    assert {:ok, :done} =
             LocalExecutor.run(
               Operation,
               input([{":a", 2, {:ok, :first}}, {":b", 3, {:ok, :second}}]),
               correlation_id: "executor-progress",
               max_concurrency: 1,
               on_progress: progress
             )

    assert_received {:progress, %{completed: 2, total: 5}}
    assert_received {:progress, %{completed: 5, total: 5}}
  end

  test "stops when progress returns an error" do
    assert {:error, :progress_failed} =
             LocalExecutor.run(Operation, input([{":a", 1, {:ok, :first}}]),
               correlation_id: "executor-progress-error",
               on_progress: fn _progress -> {:error, :progress_failed} end
             )

    refute_received {:gathered, _results}
  end

  test "limits active partition tasks" do
    input =
      input([
        {":a", 1, {:notify, self(), :first}},
        {":b", 1, {:notify, self(), :second}}
      ])

    task =
      Task.async(fn ->
        LocalExecutor.run(Operation, input,
          correlation_id: "executor-concurrency",
          max_concurrency: 1
        )
      end)

    assert_receive {:partition_started, first_task}
    refute_receive {:partition_started, _task}, 50
    send(first_task, :continue)
    assert_receive {:partition_started, second_task}
    send(second_task, :continue)
    assert {:ok, :done} = Task.await(task)
  end

  defp input(partitions, gather_result \\ {:ok, :done}) do
    %{partitions: partitions, gather_result: gather_result, test_pid: self()}
  end
end
