defmodule NetworkDefense.Evaluation2.RandomnessTest do
  @moduledoc """
  Seed schedules of the foundation boundary.

  Cases: RNG-01 (one scientific context and study seed produce one schedule, with
  required phase, row, and role separation) and the logical half of RNG-02 (a
  declaration-order change keeps the scheduled stream of the same comparison).
  """

  use ExUnit.Case, async: true
  @moduletag :unit

  import NetworkDefense.Evaluation2Test.FoundationFixtures

  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Study.Randomness

  @pilot_rows 0..29
  @final_rows 0..19

  describe "RNG-01 stable allocation" do
    test "matches independent SHA-256 JSON encoding anchors" do
      # Oracle: Python hashlib.sha256 over compact UTF-8 JSON arrays, interpreted
      # as one unsigned big-endian integer modulo 2^63 - 1.
      assert {:ok, definition} = Definition.parse(valid_attrs())
      assert Randomness.selection_seed(definition, :pilot, 0) == 3_449_400_019_685_693_375
      assert Randomness.selection_seed(definition, :final, 0) == 7_039_592_190_032_541_263
      assert Randomness.evaluation_root(definition, :pilot, "small") == 6_251_974_170_197_726_605

      assert Randomness.pilot_planning_seed(
               definition,
               comparison(definition, "small", 4, :random)
             ) == 6_188_961_418_792_346_338
    end

    test "the same document and seed reproduce every stream" do
      assert {:ok, first} = Definition.parse(valid_attrs())
      assert {:ok, second} = Definition.parse(valid_attrs())

      assert selection_schedule(first, :pilot) == selection_schedule(second, :pilot)
      assert selection_schedule(first, :final) == selection_schedule(second, :final)
      assert evaluation_roots(first) == evaluation_roots(second)
      assert planning_seeds(first) == planning_seeds(second)
    end

    test "a different study seed changes the schedule" do
      assert {:ok, default} = Definition.parse(valid_attrs())
      assert {:ok, other} = Definition.parse(attrs_with([{["seed"], 31_416}]))

      for phase <- [:pilot, :final] do
        refute selection_schedule(default, phase) == selection_schedule(other, phase),
               "the study seed must change the #{phase} selection schedule"
      end

      refute evaluation_roots(default) == evaluation_roots(other)
      refute planning_seeds(default) == planning_seeds(other)
    end

    test "Pilot and Final streams stay separated" do
      assert {:ok, definition} = Definition.parse(valid_attrs())

      for row <- 0..9 do
        refute Randomness.selection_seed(definition, :pilot, row) ==
                 Randomness.selection_seed(definition, :final, row)
      end

      for tier <- Enum.map(definition.tiers, &tier_name/1) do
        refute Randomness.evaluation_root(definition, :pilot, tier) ==
                 Randomness.evaluation_root(definition, :final, tier)
      end
    end

    test "every selection row of one phase has its own stream" do
      assert {:ok, definition} = Definition.parse(valid_attrs())

      for {phase, rows} <- [pilot: @pilot_rows, final: @final_rows] do
        seeds = Enum.map(rows, &Randomness.selection_seed(definition, phase, &1))

        assert length(seeds) == MapSet.size(MapSet.new(seeds)),
               "each #{phase} selection row must have a distinct seed"
      end
    end

    test "every produced seed is an in-range non-negative integer" do
      assert {:ok, definition} = Definition.parse(valid_attrs())

      seeds =
        selection_schedule(definition, :pilot) ++
          selection_schedule(definition, :final) ++
          Map.values(evaluation_roots(definition)) ++ Map.values(planning_seeds(definition))

      for seed <- seeds do
        assert is_integer(seed) and seed >= 0 and seed < Randomness.modulus()
      end
    end

    test "one allocation covers the planned streams without a collision" do
      assert {:ok, definition} = Definition.parse(valid_attrs())
      assert :ok = Randomness.validate(definition)
    end
  end

  describe "RNG-02 logical identity" do
    test "a reordered alternative list keeps the planning stream of one comparison" do
      assert {:ok, default} = Definition.parse(valid_attrs())

      reordered =
        attrs_with([
          {["tiers", "medium", "alternatives"],
           Enum.reverse(valid_attrs()["tiers"]["medium"]["alternatives"])}
        ])

      assert {:ok, other} = Definition.parse(reordered)

      baseline =
        Randomness.pilot_planning_seed(default, comparison(default, "medium", 4, :random))

      changed = Randomness.pilot_planning_seed(other, comparison(other, "medium", 4, :random))

      assert baseline == changed
    end

    test "a reordered candidate list keeps every planning stream" do
      assert {:ok, default} = Definition.parse(valid_attrs())

      reordered =
        attrs_with([
          {["pilot", "candidates"], Enum.reverse(valid_attrs()["pilot"]["candidates"])}
        ])

      assert {:ok, other} = Definition.parse(reordered)
      assert planning_seeds(default) == planning_seeds(other)
    end

    test "each comparison has its own planning stream" do
      assert {:ok, definition} = Definition.parse(valid_attrs())

      seeds = Map.values(planning_seeds(definition))
      assert length(seeds) == MapSet.size(MapSet.new(seeds))
    end

    test "outer subsamples derive from the comparison stream and the row or column role" do
      assert {:ok, definition} = Definition.parse(valid_attrs())
      comparison = comparison(definition, "small", 4, :random)

      row_seeds = Enum.map(0..4, &Randomness.outer_seed(definition, comparison, &1, :rows))
      column_seeds = Enum.map(0..4, &Randomness.outer_seed(definition, comparison, &1, :columns))

      assert length(row_seeds) == MapSet.size(MapSet.new(row_seeds))
      assert length(column_seeds) == MapSet.size(MapSet.new(column_seeds))
      assert Enum.zip(row_seeds, column_seeds) |> Enum.all?(fn {row, column} -> row != column end)

      assert row_seeds ==
               Enum.map(0..4, &Randomness.outer_seed(definition, comparison, &1, :rows))
    end
  end

  defp selection_schedule(definition, phase) do
    definition
    |> definition_rows(phase)
    |> Enum.map(&Randomness.selection_seed(definition, phase, &1))
  end

  defp definition_rows(definition, :pilot) do
    %{plans: plans} = Definition.pilot_capacity(definition)
    0..(plans - 1)
  end

  defp definition_rows(definition, :final) do
    definition.pilot.candidates |> Enum.map(& &1.plans) |> Enum.max() |> then(&(0..(&1 - 1)))
  end

  defp evaluation_roots(definition) do
    Map.new(definition.tiers, fn tier ->
      {tier_name(tier), Randomness.evaluation_root(definition, :pilot, tier_name(tier))}
    end)
  end

  defp planning_seeds(definition) do
    Map.new(Definition.comparisons(definition), fn comparison ->
      {identity(comparison), Randomness.pilot_planning_seed(definition, comparison)}
    end)
  end

  defp identity(comparison) do
    {tier_name(comparison), comparison.budget, strategy_name(comparison.alternative)}
  end

  defp comparison(definition, tier, budget, alternative) do
    Enum.find(Definition.comparisons(definition), &(identity(&1) == {tier, budget, alternative})) ||
      raise "the definition declares no #{inspect({tier, budget, alternative})} comparison"
  end
end
