defmodule NetworkDefense.Compute.OperationRegistryTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Compute.OperationRegistry

  test "looks up configured operations in both directions" do
    operation_module = NetworkDefense.Simulation.SimulationOperation

    assert {:ok, "simulation"} = OperationRegistry.wire_name(operation_module)
    assert {:ok, ^operation_module} = OperationRegistry.module("simulation")
  end

  test "rejects unsupported modules" do
    assert {:error, :unsupported_operation} = OperationRegistry.wire_name(:unsupported)
    assert {:error, :unsupported_operation} = OperationRegistry.wire_name("simulation")
  end

  test "rejects unknown and malformed names" do
    assert {:error, :unknown_operation} = OperationRegistry.module("other")
    assert {:error, :unknown_operation} = OperationRegistry.module("")
    assert {:error, :unknown_operation} = OperationRegistry.module(:simulation)
  end
end
