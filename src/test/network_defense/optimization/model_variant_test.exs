defmodule NetworkDefense.Optimization.ModelVariantTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Optimization.{ModelVariant, SimulationObjective}

  test "round-trips canonical values without creating atoms" do
    for variant <- ModelVariant.values() do
      assert {:ok, ^variant} = ModelVariant.from_wire(Atom.to_string(variant))
      assert ModelVariant.to_wire(variant) == Atom.to_string(variant)
    end

    unknown = "unknown_variant_#{System.unique_integer([:positive])}"

    assert {:ok, :mission_impact_only} = SimulationObjective.from_wire("mission_impact_only")
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
    assert :error = ModelVariant.from_wire(unknown)
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
    assert :error = SimulationObjective.from_wire("unknown_objective")
  end
end
