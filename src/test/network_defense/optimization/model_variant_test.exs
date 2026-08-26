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

  test "defines all six canonical variants immutably" do
    assert %{objective: :blast_radius_only, require_pre_attack_feasibility: true} =
             ModelVariant.definition(:blast_only)

    assert %{objective: :blast_radius_only, require_pre_attack_feasibility: false} =
             ModelVariant.definition(:blast_only_unconstrained)

    assert %{objective: :mission_impact_only, require_pre_attack_feasibility: true} =
             ModelVariant.definition(:mission_only)

    assert %{objective: :mission_impact_only, require_pre_attack_feasibility: false} =
             ModelVariant.definition(:mission_only_unconstrained)

    assert %{objective: :mission_then_blast_radius, require_pre_attack_feasibility: true} =
             ModelVariant.definition(:full)

    assert %{objective: :mission_then_blast_radius, require_pre_attack_feasibility: false} =
             ModelVariant.definition(:full_unconstrained)
  end
end
