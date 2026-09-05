defmodule NetworkDefense.Compute.ScatterGatherTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Compute.ScatterGather
  alias NetworkDefense.Compute.ScatterGather.Executor
  alias NetworkDefense.TestScatterGatherOperation, as: Operation

  test "defines scatter, execute, and gather callbacks" do
    assert Enum.sort(ScatterGather.behaviour_info(:callbacks)) ==
             Enum.sort(scatter: 1, execute: 1, gather: 3)
  end

  test "defines the executor run callback" do
    assert Executor.behaviour_info(:callbacks) == [run: 3]
  end

  test "runs an operation through the configured executor" do
    input = %{
      partitions: [{:first, 1, {:ok, :result}}],
      gather_result: {:ok, :done},
      test_pid: self()
    }

    assert {:ok, :done} = ScatterGather.run(Operation, input, correlation_id: "facade-success")
    assert_received {:gathered, [{:first, :result}]}
  end
end
