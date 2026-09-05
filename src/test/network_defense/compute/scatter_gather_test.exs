defmodule NetworkDefense.Compute.ScatterGatherTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Compute.ScatterGather
  alias NetworkDefense.Compute.ScatterGather.Executor

  test "defines scatter, execute, and gather callbacks" do
    assert Enum.sort(ScatterGather.behaviour_info(:callbacks)) ==
             Enum.sort(scatter: 1, execute: 1, gather: 3)
  end

  test "defines the executor run callback" do
    assert Executor.behaviour_info(:callbacks) == [run: 3]
  end
end
