defmodule NetworkDefense.Evaluation2.DerivedViewsTest do
  @moduledoc """
  Derived comparison, group, and capacity views of one trusted definition.

  The expected orders are transcribed from the declared fixture document and
  from the documented derivation rules, so a wrong order or count fails:

    * comparisons: tier order, declared budget order, declared alternative order
    * groups: tier order, declared budget order, CVSS and then declared alternatives
    * capacity: the largest declared candidate pair plus the declared extra pool

  Cases: MODEL-01 (derived dimensions and canonical order), COL-01 (one shared
  CVSS group projected into comparisons of the same tier and budget).
  """

  use ExUnit.Case, async: true
  @moduletag :unit

  import NetworkDefense.Evaluation2Test.FoundationFixtures

  alias NetworkDefense.Evaluation2.Study.Definition

  @expected_comparisons [
    {"small", 4, :random},
    {"small", 4, :simulation_informed},
    {"small", 8, :random},
    {"small", 8, :simulation_informed},
    {"medium", 8, :simulation_informed},
    {"medium", 8, :random},
    {"medium", 4, :simulation_informed},
    {"medium", 4, :random},
    {"large", 4, :random}
  ]

  @expected_groups [
    {"small", 4, :cvss},
    {"small", 4, :random},
    {"small", 4, :simulation_informed},
    {"small", 8, :cvss},
    {"small", 8, :random},
    {"small", 8, :simulation_informed},
    {"medium", 8, :cvss},
    {"medium", 8, :simulation_informed},
    {"medium", 8, :random},
    {"medium", 4, :cvss},
    {"medium", 4, :simulation_informed},
    {"medium", 4, :random},
    {"large", 4, :cvss},
    {"large", 4, :random}
  ]

  describe "MODEL-01 comparison view" do
    test "returns every declared comparison in canonical order" do
      assert {:ok, definition} = Definition.parse(valid_attrs())

      comparisons = Definition.comparisons(definition)

      assert Enum.count(comparisons) == 9

      assert Enum.map(comparisons, fn comparison ->
               {tier_name(comparison), comparison.budget, strategy_name(comparison.alternative)}
             end) == @expected_comparisons
    end

    test "compares every alternative against the one implicit CVSS reference" do
      assert {:ok, definition} = Definition.parse(valid_attrs())
      comparisons = Definition.comparisons(definition)

      assert comparisons |> Enum.map(&strategy_name(&1.reference)) |> Enum.uniq() == [:cvss]

      for comparison <- comparisons do
        refute strategy_name(comparison.alternative) == strategy_name(comparison.reference)
      end
    end

    test "gives every comparison the same measured outcome" do
      assert {:ok, definition} = Definition.parse(valid_attrs())
      outcomes = Definition.comparisons(definition) |> Enum.map(& &1.outcome) |> Enum.uniq()

      assert [outcome] = outcomes
      assert is_binary(outcome) and outcome != ""
    end
  end

  describe "COL-01 physical group view" do
    test "returns one group per tier, budget, and strategy in canonical order" do
      assert {:ok, definition} = Definition.parse(valid_attrs())

      groups = Definition.collection_groups(definition)

      assert Enum.count(groups) == 14

      assert Enum.map(groups, fn group ->
               {tier_name(group), group.budget, strategy_name(group)}
             end) == @expected_groups
    end

    test "counts the CVSS reference once per declared budget" do
      assert {:ok, definition} = Definition.parse(valid_attrs())
      groups = Definition.collection_groups(definition)

      references =
        groups
        |> Enum.filter(&(strategy_name(&1) == :cvss))
        |> Enum.map(&{tier_name(&1), &1.budget})

      assert references == [
               {"small", 4},
               {"small", 8},
               {"medium", 8},
               {"medium", 4},
               {"large", 4}
             ]
    end

    test "keeps one global group position per physical group" do
      assert {:ok, definition} = Definition.parse(valid_attrs())

      positions = definition |> Definition.collection_groups() |> Enum.map(&group_position/1)

      assert positions == Enum.to_list(0..13)
    end

    test "projects the shared CVSS group into every comparison of its context" do
      assert {:ok, definition} = Definition.parse(valid_attrs())

      groups = Definition.collection_groups(definition)
      reference_positions = reference_group_positions(groups)

      for comparison <- Definition.comparisons(definition) do
        context = {tier_name(comparison), comparison.budget}

        assert comparison.reference_group_position == Map.fetch!(reference_positions, context),
               "comparison #{inspect(context)} must project the CVSS group of its context"

        assert strategy_name(Enum.at(groups, group_position(comparison))) ==
                 strategy_name(comparison.alternative)

        refute comparison.group_position == comparison.reference_group_position
      end
    end
  end

  describe "MODEL-01 Pilot capacity" do
    test "derives the collected dimensions from the largest candidate and the extra pool" do
      assert {:ok, definition} = Definition.parse(valid_attrs())

      assert %{plans: 30, attacks: 60} = Definition.pilot_capacity(definition)
    end

    test "derives capacity from the largest candidate regardless of declaration order" do
      reversed =
        attrs_with([
          {["pilot", "candidates"], Enum.reverse(valid_attrs()["pilot"]["candidates"])}
        ])

      assert {:ok, definition} = Definition.parse(reversed)
      assert %{plans: 30, attacks: 60} = Definition.pilot_capacity(definition)
    end

    test "keeps the largest candidate pair when the extra pool is empty" do
      attrs = attrs_with([{["pilot", "extra_pool"], %{"plans" => 0, "attacks" => 0}}])

      assert {:ok, definition} = Definition.parse(attrs)
      assert %{plans: 20, attacks: 40} = Definition.pilot_capacity(definition)
    end

    test "adds a declared extra pool to the largest candidate pair" do
      attrs =
        attrs_with([
          {["pilot", "extra_pool"], %{"plans" => 5, "attacks" => 7}},
          {["pilot", "candidates"], [%{"id" => "only", "plans" => 3, "attacks" => 11}]}
        ])

      assert {:ok, definition} = Definition.parse(attrs)
      assert %{plans: 8, attacks: 18} = Definition.pilot_capacity(definition)
    end
  end

  defp reference_group_positions(groups) do
    groups
    |> Enum.filter(&(strategy_name(&1) == :cvss))
    |> Map.new(fn group -> {{tier_name(group), group.budget}, group_position(group)} end)
  end
end
