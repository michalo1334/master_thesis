defmodule NetworkDefense.Evaluation2.ComputeTest do
  @moduledoc """
  Mathematical behavior of the native fixed-sample numerical kernel.

  Cases: NUM-01 (matching cover, rectangular orientations, arithmetic averaging
  across matchings), NUM-02 (Pilot outer subsets and guard quantile), NUM-03
  (monotone conservative intervals), NUM-04 (rare-event and degenerate samples),
  NUM-05 (scale behavior and repeatability), NUM-06 (frozen model bounds),
  HOLM-01 (decimal family correction).

  Expected values come from `NetworkDefense.Evaluation2Test.NumericAnchors`,
  which implements the documented method independently in plain sequential
  Elixir. No expectation is read from the kernel. The fixtures are closed-form
  matrices, so the cases need no random stream.

  Tag `:slow` marks the extreme-horizon underflow probe, which needs a horizon
  near 1850 and therefore minutes on the binary backend. It exists only when
  `EVALUATION2_SLOW_NUMERICS=1` is set, so the default suite stays fast:
  `EVALUATION2_SLOW_NUMERICS=1 mix test test/network_defense/evaluation2/compute_test.exs`.
  """

  use ExUnit.Case, async: true
  @moduletag :unit

  alias NetworkDefense.Evaluation2.Study.Compute
  alias NetworkDefense.Evaluation2Test.NumericAnchors, as: Anchor

  @confidence 0.95

  describe "NUM-01 fixed matching cover" do
    test "the cyclic cover partitions every cell once in both orientations" do
      for {rows, columns} <- [{2, 3}, {3, 2}, {1, 5}, {5, 1}, {20, 25}, {25, 20}] do
        matchings = Anchor.cover(rows, columns)
        horizon = min(rows, columns)

        assert length(matchings) == max(rows, columns)
        assert Enum.all?(matchings, &(length(&1) == horizon))

        for matching <- matchings do
          assert Enum.map(matching, &elem(&1, 0)) |> Enum.uniq() |> length() == horizon
          assert Enum.map(matching, &elem(&1, 1)) |> Enum.uniq() |> length() == horizon
        end

        cells = List.flatten(matchings)
        assert length(cells) == rows * columns
        assert Enum.uniq(cells) |> length() == rows * columns

        assert MapSet.new(cells) ==
                 MapSet.new(for i <- 0..(rows - 1), j <- 0..(columns - 1), do: {i, j})
      end
    end

    test "rectangular matrices match the independent reference in both orientations" do
      alternative = fn i, j -> 0.42 + 0.02 * rem(2 * i + 3 * j, 4) / 3 end
      reference = fn i, j -> 0.5 + 0.01 * rem(i + 5 * j, 3) / 2 end

      for {rows, columns} <- [{20, 25}, {25, 20}] do
        alt = Anchor.build(rows, columns, alternative)
        ref = Anchor.build(rows, columns, reference)
        expected = Anchor.reference_compare(alt, ref, 0.0, 1.0, @confidence)

        assert {:ok, actual} = Compute.compare(input(alt, ref), inference())

        assert_in_delta actual.estimate, expected.estimate, 1.0e-12
        assert_in_delta actual.lower, expected.lower, 1.0e-9
        assert_in_delta actual.upper, expected.upper, 1.0e-9
        assert_in_delta actual.p_value, expected.p_value, expected.p_value * 1.0e-9
        assert_in_delta actual.half_width, expected.half_width, 1.0e-9
      end
    end

    test "constant columns add no evidence beyond the matching horizon" do
      anchored = Anchor.constant_contrast(-0.05, 1.0, 20, @confidence)

      for {rows, columns} <- [{20, 25}, {20, 60}, {25, 20}, {60, 20}] do
        alt = Anchor.build(rows, columns, fn _, _ -> 0.45 end)
        ref = Anchor.build(rows, columns, fn _, _ -> 0.5 end)

        assert {:ok, actual} = Compute.compare(input(alt, ref), inference())

        # The horizon is min(rows, columns) = 20 for every one of these shapes.
        assert_in_delta actual.p_value, anchored.p_value, 1.0e-12
        assert_in_delta actual.lower, anchored.lower, 1.0e-9
        assert_in_delta actual.upper, anchored.upper, 1.0e-9
        assert actual.warnings == []
      end
    end
  end

  describe "NUM-04 rare events and degeneracy" do
    test "a five-row rare-event contrast is not point certainty" do
      # Executed counterexample shape: five plan rows observed at zero against a
      # constant reference of 0.1, so the whole sample is the constant -0.1.
      alt = Anchor.build(5, 10, fn _, _ -> 0.0 end)
      ref = Anchor.build(5, 10, fn _, _ -> 0.1 end)
      expected = Anchor.reference_compare(alt, ref, 0.0, 1.0, @confidence)

      assert {:ok, actual} = Compute.compare(input(alt, ref), inference())

      assert actual.p_value == 1.0
      assert_in_delta actual.estimate, -0.1, 1.0e-12
      assert_in_delta actual.half_width, expected.half_width, 1.0e-9
      assert actual.lower < actual.estimate and actual.estimate < actual.upper
      assert actual.upper - actual.lower > 1.0
      assert actual.informative
      assert actual.warnings == []
    end

    test "observed zero contrast keeps a nondegenerate interval" do
      # Identical sides: the sample shows equality, which is not population
      # certainty, because the rows could vary in a fresh sample.
      alt = Anchor.build(6, 9, fn i, j -> 0.2 + 0.05 * rem(i + j, 3) end)
      expected = Anchor.reference_compare(alt, alt, 0.0, 1.0, @confidence)

      assert {:ok, actual} = Compute.compare(input(alt, alt), inference())

      assert actual.p_value == 1.0
      assert actual.estimate == 0.0
      assert actual.lower < 0.0 and actual.upper > 0.0
      assert_in_delta actual.half_width, expected.half_width, 1.0e-9
    end

    test "a structural zero range reports exact equality" do
      same = Anchor.build(4, 3, fn _, _ -> 0.5 end)

      assert {:ok, actual} =
               Compute.compare(
                 %{
                   alternative: same,
                   reference: same,
                   lower_bound: 0.5,
                   upper_bound: 0.5
                 },
                 inference()
               )

      assert actual.estimate == 0.0
      assert actual.lower == 0.0
      assert actual.upper == 0.0
      assert actual.half_width == 0.0
      assert actual.p_value == 1.0
      assert actual.warnings == []
    end
  end

  describe "NUM-03 conservative interval policy" do
    test "endpoints bracket the estimate and widen with confidence" do
      alt = Anchor.build(20, 25, fn i, j -> 0.42 + 0.02 * rem(2 * i + 3 * j, 4) / 3 end)
      ref = Anchor.build(20, 25, fn i, j -> 0.5 + 0.01 * rem(i + 5 * j, 3) / 2 end)

      results =
        for level <- [0.8, 0.95, 0.99] do
          assert {:ok, result} = Compute.compare(input(alt, ref), %{confidence_level: level})
          result
        end

      for result <- results do
        assert result.lower <= result.estimate
        assert result.estimate <= result.upper
        assert result.lower >= -1.0 and result.upper <= 1.0
        assert_in_delta result.half_width, result.upper / 2 - result.lower / 2, 1.0e-12
        assert_in_delta result.estimate, -0.07512333333333338, 1.0e-12
      end

      [eighty, ninety_five, ninety_nine] = results
      assert ninety_five.lower <= eighty.lower
      assert ninety_five.upper >= eighty.upper
      assert ninety_nine.lower <= ninety_five.lower
      assert ninety_nine.upper >= ninety_five.upper
    end

    test "reported endpoints sit on the conservative side of the reference brackets" do
      alt = Anchor.build(20, 25, fn i, j -> 0.42 + 0.02 * rem(2 * i + 3 * j, 4) / 3 end)
      ref = Anchor.build(20, 25, fn i, j -> 0.5 + 0.01 * rem(i + 5 * j, 3) / 2 end)
      expected = Anchor.reference_compare(alt, ref, 0.0, 1.0, @confidence)

      assert {:ok, actual} = Compute.compare(input(alt, ref), inference())

      # Inversion keeps outer brackets, so a wider interval is acceptable and a
      # narrower one is not.
      assert actual.lower <= expected.lower + 1.0e-9
      assert actual.upper >= expected.upper - 1.0e-9
      assert_in_delta actual.lower, expected.lower, 1.0e-8
      assert_in_delta actual.upper, expected.upper, 1.0e-8
    end

    test "saturated brackets clip to the known contrast range" do
      # A two-row contrast cannot reach the inversion threshold, so both
      # endpoints leave the normalized domain and clip to the known range.
      alt = Anchor.build(2, 4, fn i, j -> 0.2 + 0.1 * rem(i + j, 2) end)
      ref = Anchor.build(2, 4, fn i, j -> 0.3 + 0.1 * rem(i + 2 * j, 2) end)
      expected = Anchor.reference_compare(alt, ref, 0.0, 1.0, @confidence)

      assert {:ok, actual} = Compute.compare(input(alt, ref), inference())

      assert actual.lower >= -1.0
      assert actual.upper <= 1.0
      assert_in_delta actual.lower, expected.lower, 1.0e-9
      assert_in_delta actual.upper, expected.upper, 1.0e-9
    end
  end

  describe "NUM-05 scale and repeatability" do
    test "rescaling outcomes and bounds scales the interval and keeps decisions" do
      alt = Anchor.build(5, 8, fn i, j -> 0.1 + 0.3 * rem(2 * i + 3 * j, 5) / 5 end)
      ref = Anchor.build(5, 8, fn i, j -> 0.2 + 0.25 * rem(i + j, 4) / 4 end)

      assert {:ok, unit} = Compute.compare(input(alt, ref), inference())

      scaled_alt = scale(alt, 3.0)
      scaled_ref = scale(ref, 3.0)

      assert {:ok, scaled} =
               Compute.compare(
                 %{
                   alternative: scaled_alt,
                   reference: scaled_ref,
                   lower_bound: 0.0,
                   upper_bound: 3.0
                 },
                 inference()
               )

      assert_in_delta scaled.estimate, 3 * unit.estimate, 1.0e-12
      assert_in_delta scaled.lower, 3 * unit.lower, 1.0e-9
      assert_in_delta scaled.upper, 3 * unit.upper, 1.0e-9
      assert_in_delta scaled.half_width, 3 * unit.half_width, 1.0e-9
      assert scaled.p_value == unit.p_value
      assert scaled.informative == unit.informative

      expected =
        Anchor.reference_compare(alt, ref, 0.0, 1.0, @confidence)

      assert_in_delta unit.estimate, expected.estimate, 1.0e-12
      assert_in_delta unit.p_value, expected.p_value, expected.p_value * 1.0e-9
    end

    test "repeated analysis of the same input is identical" do
      alt = Anchor.build(20, 25, fn i, j -> 0.42 + 0.02 * rem(2 * i + 3 * j, 4) / 3 end)
      ref = Anchor.build(20, 25, fn i, j -> 0.5 + 0.01 * rem(i + 5 * j, 3) / 2 end)

      assert {:ok, first} = Compute.compare(input(alt, ref), inference())
      assert {:ok, second} = Compute.compare(input(alt, ref), inference())

      # Final inference is deterministic: no bootstrap or null-draw stream.
      assert first == second
    end
  end

  describe "NUM-06 frozen model bounds" do
    test "invalid inputs are rejected at the boundary" do
      alt = Anchor.build(4, 3, fn i, j -> 0.1 + 0.1 * rem(i + j, 3) end)
      ref = Anchor.build(4, 3, fn i, j -> 0.2 + 0.1 * rem(i + 2 * j, 3) end)

      assert {:error, :non_rectangular} =
               Compute.compare(input([[0.1, 0.2], [0.3]], ref), inference())

      assert {:error, :shape_mismatch} =
               Compute.compare(input(alt, Anchor.build(4, 4, fn _, _ -> 0.2 end)), inference())

      assert {:error, :empty_side} = Compute.compare(input([], []), inference())

      assert {:error, :inverted_bounds} =
               Compute.compare(
                 %{
                   alternative: alt,
                   reference: ref,
                   lower_bound: 1.0,
                   upper_bound: 0.0
                 },
                 inference()
               )

      assert {:error, :invalid_confidence_level} =
               Compute.compare(input(alt, ref), %{confidence_level: 1.0})

      # The observed sample stays inside the frozen model range.
      over = [[1.2, 0.3, 0.4], [0.5, 0.6, 0.7], [0.1, 0.2, 0.3], [0.4, 0.5, 0.6]]
      assert {:error, :out_of_range} = Compute.compare(input(over, ref), inference())

      huge = Integer.pow(10, 400)

      assert {:error, :non_finite_observation} =
               Compute.compare(input([[huge, 0.2, 0.3], [0.4, 0.5, 0.6]], ref), inference())

      assert {:error, :non_finite_bound} =
               Compute.compare(
                 %{
                   alternative: alt,
                   reference: ref,
                   lower_bound: 0.0,
                   upper_bound: huge
                 },
                 inference()
               )
    end
  end

  describe "HOLM-01 family correction" do
    test "adjustments follow the exact cumulative procedure with ties" do
      # Two tied raw p-values, cumulative maximum, and a capped adjustment:
      # 3 * 0.03125 = 0.09375, then max(0.09375, 2 * 0.03125) = 0.09375, then 1.0.
      p_values = [0.03125, 0.03125, 1.0]

      assert [
               %{p_value: 0.03125, adjusted_p_value: 0.09375, reject?: true},
               %{p_value: 0.03125, adjusted_p_value: 0.09375, reject?: true},
               %{p_value: 1.0, adjusted_p_value: 1.0, reject?: false}
             ] = Compute.holm(p_values, 0.1)

      expected = Anchor.holm(p_values, 0.1)
      assert_adjustments_match(Compute.holm(p_values, 0.1), expected, 0.1)

      # One step stricter: the same family no longer rejects.
      refuted = Compute.holm(p_values, 0.09)
      assert Enum.all?(refuted, &(&1.reject? == false))
      assert_adjustments_match(refuted, Anchor.holm(p_values, 0.09), 0.09)
    end

    test "the decision is inclusive at an exactly representable alpha" do
      # 2 * 0.0625 = 0.125 exactly, so alpha = 0.125 rejects and 0.1249 does not.
      p_values = [0.0625, 0.5]

      assert [%{reject?: true}, %{reject?: false}] = Compute.holm(p_values, 0.125)
      assert [%{reject?: false}, %{reject?: false}] = Compute.holm(p_values, 0.1249)

      for alpha <- [0.125, 0.1249, 0.05, 0.5] do
        for row <- Compute.holm(p_values, alpha) do
          assert row.reject? == row.adjusted_p_value <= alpha
        end
      end
    end

    test "order and membership of the family are preserved" do
      # Unsorted input: the canonical order must come back unchanged.
      p_values = [0.5, 0.0625, 0.25]
      result = Compute.holm(p_values, 0.05)

      assert Enum.map(result, & &1.p_value) == p_values
      assert_adjustments_match(result, Anchor.holm(p_values, 0.05), 0.05)
    end

    test "a 36-member family rejects the anchored 160-pair p-value in first position" do
      # Independent anchor: 160 constant pairs at contrast -0.1 with range 1.
      anchored = Anchor.constant_contrast(-0.1, 1.0, 160, @confidence)
      assert_in_delta anchored.p_value, 0.0008718, 0.0008718 * 1.0e-4

      alt = Anchor.build(160, 160, fn _, _ -> 0.4 end)
      ref = Anchor.build(160, 160, fn _, _ -> 0.5 end)

      assert {:ok, comparison} = Compute.compare(input(alt, ref), inference())

      assert_in_delta comparison.p_value, anchored.p_value, anchored.p_value * 1.0e-9

      family = [comparison.p_value | List.duplicate(1.0, 35)]
      [first | rest] = Compute.holm(family, 0.05)

      assert first.reject?
      assert_in_delta first.adjusted_p_value, 36 * comparison.p_value, 1.0e-9
      assert Enum.all?(rest, &(&1.adjusted_p_value == 1.0 and &1.reject? == false))

      # The same family is not significant at a stricter alpha.
      assert [%{reject?: false} | _] = Compute.holm(family, 0.03)
    end
  end

  describe "NUM-02 Pilot precision planning" do
    test "the guarded half-width is the declared linear-interpolation quantile" do
      pool = pilot_pool()

      assert {:ok, result} =
               Compute.pilot_precision(
                 input(pool.alternative, pool.reference),
                 %{plans: 16, attacks: 20},
                 %{outer_subsamples: 8, guard_quantile: 0.9},
                 inference(),
                 20_261_030
               )

      assert Enum.count(result.half_widths) == 8
      assert Enum.all?(result.half_widths, &(is_float(&1) and &1 >= 0.0))
      assert is_boolean(result.informative)
      assert result.guarded_half_width >= Enum.min(result.half_widths)
      assert result.guarded_half_width <= Enum.max(result.half_widths)

      assert_in_delta result.guarded_half_width,
                      Anchor.quantile(result.half_widths, 0.9),
                      1.0e-12
    end

    test "the same seed reproduces the guarded widths" do
      pool = pilot_pool()

      plan = fn seed ->
        Compute.pilot_precision(
          input(pool.alternative, pool.reference),
          %{plans: 16, attacks: 20},
          %{outer_subsamples: 8, guard_quantile: 0.9},
          inference(),
          seed
        )
      end

      assert {:ok, first} = plan.(20_261_030)
      assert {:ok, second} = plan.(20_261_030)
      assert first.half_widths == second.half_widths

      assert {:ok, other} = plan.(20_261_031)
      assert other.half_widths != first.half_widths
    end

    test "a stricter guard quantile and a higher confidence never narrow the guard" do
      pool = pilot_pool()

      guard = fn quantile, level ->
        assert {:ok, result} =
                 Compute.pilot_precision(
                   input(pool.alternative, pool.reference),
                   %{plans: 16, attacks: 20},
                   %{outer_subsamples: 8, guard_quantile: quantile},
                   %{confidence_level: level},
                   20_261_030
                 )

        result.guarded_half_width
      end

      assert guard.(0.5, @confidence) <= guard.(0.9, @confidence)
      assert guard.(0.9, 0.99) >= guard.(0.9, @confidence)
    end

    test "an impossible candidate size is rejected" do
      pool = pilot_pool()

      assert {:error, :invalid_pilot_precision} =
               Compute.pilot_precision(
                 input(pool.alternative, pool.reference),
                 %{plans: 21, attacks: 20},
                 %{outer_subsamples: 8, guard_quantile: 0.9},
                 inference(),
                 20_261_030
               )

      assert {:error, :invalid_pilot_precision} =
               Compute.pilot_precision(
                 input(pool.alternative, pool.reference),
                 %{plans: 16, attacks: 26},
                 %{outer_subsamples: 8, guard_quantile: 0.9},
                 inference(),
                 20_261_030
               )

      assert {:error, :invalid_pilot_precision} =
               Compute.pilot_precision(
                 input(pool.alternative, pool.reference),
                 %{plans: 0, attacks: 20},
                 %{outer_subsamples: 8, guard_quantile: 0.9},
                 inference(),
                 20_261_030
               )
    end
  end

  # The extreme-horizon probe costs minutes on the binary backend, so it only
  # exists when explicitly requested. The statistical runner repeats it as a
  # declared boundary probe.
  if System.get_env("EVALUATION2_SLOW_NUMERICS") == "1" do
    describe "extreme numerical boundaries" do
      @tag :slow
      @tag timeout: 900_000
      test "capital underflow floors the p-value at the smallest normal float" do
        # A horizon of 1850 identical pairs grows the directional capital past
        # exp(709), so the raw p-value leaves the representable range. The method
        # floors it instead of reporting zero evidence weight.
        pairs = 1850
        anchored = Anchor.constant_contrast(-1.0, 1.0, pairs, @confidence)

        assert elem(anchored.log_capitals, 1) > 709.0

        zero = List.duplicate(List.duplicate(0.0, pairs), pairs)
        one = List.duplicate(List.duplicate(1.0, pairs), pairs)

        assert {:ok, result} = Compute.compare(input(zero, one), inference())

        # Smallest normal float64, the documented underflow floor.
        assert result.p_value == 2.2250738585072014e-308
        assert result.p_value > 0.0
        assert result.p_value < 1.0e-300
        assert result.estimate == -1.0
        assert result.lower >= -1.0
        assert result.warnings == []
      end
    end
  end

  ## Fixtures and helpers

  # A 20 by 25 Pilot pool with mild row and column variation.
  defp pilot_pool do
    %{
      alternative: Anchor.build(20, 25, fn i, j -> 0.42 + 0.02 * rem(2 * i + 3 * j, 4) / 3 end),
      reference: Anchor.build(20, 25, fn i, j -> 0.5 + 0.01 * rem(i + 5 * j, 3) / 2 end)
    }
  end

  defp input(alternative, reference) do
    %{alternative: alternative, reference: reference, lower_bound: 0.0, upper_bound: 1.0}
  end

  defp inference, do: %{confidence_level: @confidence}

  defp scale(rows, factor), do: Enum.map(rows, fn row -> Enum.map(row, &(&1 * factor)) end)

  defp assert_adjustments_match(actual, expected, alpha) do
    assert length(actual) == length(expected)

    for {row, anchor} <- Enum.zip(actual, expected) do
      assert row.p_value == anchor.p_value
      assert row.reject? == anchor.reject?
      assert_in_delta row.adjusted_p_value, Decimal.to_float(anchor.adjusted_p_value), 1.0e-12
      assert row.reject? == row.adjusted_p_value <= alpha
    end
  end
end
