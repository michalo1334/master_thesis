defmodule NetworkDefense.Evaluation2.ComputePolicyTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Evaluation2.Study.Compute
  alias NetworkDefense.Evaluation2.Study.Compute.{Betting, PilotPrecision}

  @moduletag :unit

  test "NUM-01 WHEN two short capitals differ THEN their average SHALL match hand products" do
    xs = Nx.tensor([[0.1, 0.2], [0.7, 0.9]], type: :f64)
    prepared = Betting.prepare(xs, 0.05)
    {plus, minus} = Betting.log_capitals(prepared, 0.5)
    # At horizon two the half-range cap binds every bet to one.
    assert_in_delta :math.exp(plus), (0.6 * 0.7 + 1.2 * 1.4) / 2, 1.0e-14
    assert_in_delta :math.exp(minus), (1.4 * 1.3 + 0.8 * 0.6) / 2, 1.0e-14
  end

  test "NUM-01 WHEN matchings differ THEN each capital SHALL use only its own past" do
    first = for index <- 0..99, do: 0.2 + rem(index, 7) / 20
    second = for index <- 0..99, do: 0.7 - rem(index, 11) / 25
    xs = Nx.tensor([first, second], type: :f64)
    together = Betting.prepare(xs, 0.05)
    {plus, minus} = Betting.log_capitals(together, 0.4)

    individual =
      for row <- Nx.to_list(xs) do
        row
        |> then(&Nx.tensor([&1], type: :f64))
        |> Betting.prepare(0.05)
        |> Betting.log_capitals(0.4)
      end

    expected_plus = :math.log(Enum.sum(Enum.map(individual, &:math.exp(elem(&1, 0)))) / 2)
    expected_minus = :math.log(Enum.sum(Enum.map(individual, &:math.exp(elem(&1, 1)))) / 2)
    assert_in_delta plus, expected_plus, 1.0e-12
    assert_in_delta minus, expected_minus, 1.0e-12
  end

  test "NUM-04 WHEN a capital overflows in ordinary space THEN the p-value SHALL retain a positive conservative floor" do
    xs = Nx.broadcast(Nx.tensor(1.0, type: :f64), {1, 2048})
    prepared = Betting.prepare(xs, 0.05)
    {plus, _minus} = Betting.log_capitals(prepared, 0.5)
    assert plus > 710
    assert Betting.p_value(prepared, 0.5) == 2.2250738585072014e-308
    assert Betting.p_value(prepared, -0.5) == 1.0
    assert Betting.p_value(prepared, 0.0) == 1.0
  end

  test "NUM-02 WHEN candidate counts grow THEN subset prefix sets SHALL remain nested and aligned" do
    smaller = PilotPrecision.subsets(9, 13, %{plans: 3, attacks: 4}, 5, 20_261_030)
    larger = PilotPrecision.subsets(9, 13, %{plans: 6, attacks: 8}, 5, 20_261_030)

    for {{small_rows, small_columns}, {large_rows, large_columns}} <- Enum.zip(smaller, larger) do
      assert small_rows == Enum.sort(Enum.uniq(small_rows))
      assert small_columns == Enum.sort(Enum.uniq(small_columns))
      assert [_, _, _] = small_rows
      assert [_, _, _, _] = small_columns
      assert Enum.all?(small_rows, &(&1 in large_rows))
      assert Enum.all?(small_columns, &(&1 in large_columns))
    end

    assert smaller == PilotPrecision.subsets(9, 13, %{plans: 3, attacks: 4}, 5, 20_261_030)
    assert smaller != PilotPrecision.subsets(9, 13, %{plans: 3, attacks: 4}, 5, 20_261_031)
  end

  test "NUM-03 WHEN a full pool is sampled THEN logical order SHALL erase permutation variation" do
    input = %{
      alternative: [[0.1, 0.7, 0.3], [0.9, 0.2, 0.4]],
      reference: [[0.5, 0.5, 0.5], [0.5, 0.5, 0.5]],
      lower_bound: 0.0,
      upper_bound: 1.0
    }

    assert {:ok, assessment} =
             Compute.pilot_precision(
               input,
               %{plans: 2, attacks: 3},
               %{outer_subsamples: 3, guard_quantile: 0.9},
               %{confidence_level: 0.95},
               17
             )

    assert [_] = Enum.uniq(assessment.half_widths)
    assert_in_delta PilotPrecision.quantile([1.0, 2.0, 5.0, 10.0], 0.5), 3.5, 1.0e-14
    assert_in_delta PilotPrecision.quantile([1.0, 2.0, 5.0, 10.0], 0.9), 8.5, 1.0e-14
  end

  test "HOLM-01 WHEN raw p-values are subnormal THEN Decimal decisions SHALL remain representable" do
    [first, second] = Compute.holm([5.0e-324, 0.5], 0.05)
    assert first.reject?
    assert first.adjusted_p_value > 0.0
    assert first.adjusted_p_value <= 0.05
    refute second.reject?
  end

  test "NUM-02 WHEN planning settings are malformed THEN the kernel SHALL return a bounded error" do
    input = %{alternative: [[0.2]], reference: [[0.3]], lower_bound: 0.0, upper_bound: 1.0}
    precision = %{outer_subsamples: 2, guard_quantile: 0.9}

    for {size, settings} <- [
          {%{attacks: 1}, precision},
          {5, precision},
          {%{plans: 1, attacks: 1}, 5}
        ] do
      assert {:error, :invalid_pilot_precision} =
               Compute.pilot_precision(input, size, settings, %{confidence_level: 0.95}, 1)
    end
  end

  test "HOLM-01 WHEN decimal multiplication reaches alpha THEN the inclusive decision SHALL use decimal arithmetic" do
    [first | _] = Compute.holm([0.07, 1.0, 1.0], 0.21)
    assert first.reject?
    assert first.adjusted_p_value <= 0.21
  end

  test "HOLM-01 WHEN float rounding crosses alpha THEN the emitted value SHALL preserve the decimal decision" do
    # Decimal doubling gives 0.0023992802159352196. Its nearest float rounds
    # down to alpha, although the exact Decimal comparison does not reject.
    alpha = 0.0023992802159352195
    [first | _] = Compute.holm([0.0011996401079676098, 1.0], alpha)
    refute first.reject?
    assert first.adjusted_p_value > alpha
  end

  test "NUM-05 WHEN non-binary bounds scale THEN float64 p-values SHALL remain unchanged" do
    input = %{
      alternative:
        for(row <- 0..19, do: for(column <- 0..29, do: 0.2 + rem(row + column, 5) / 20)),
      reference: List.duplicate(List.duplicate(0.5, 30), 20),
      lower_bound: 0.0,
      upper_bound: 1.0
    }

    scale = 8.3

    scaled = %{
      input
      | alternative: Enum.map(input.alternative, fn row -> Enum.map(row, &(&1 * scale)) end),
        reference: Enum.map(input.reference, fn row -> Enum.map(row, &(&1 * scale)) end),
        upper_bound: scale
    }

    assert {:ok, base} = Compute.compare(input, %{confidence_level: 0.95})
    assert {:ok, changed} = Compute.compare(scaled, %{confidence_level: 0.95})
    assert_in_delta base.p_value, changed.p_value, 1.0e-12
    assert_in_delta base.estimate * scale, changed.estimate, 1.0e-12
    assert_in_delta base.lower * scale, changed.lower, 1.0e-12
    assert_in_delta base.upper * scale, changed.upper, 1.0e-12
  end

  test "NUM-06 WHEN an integer exceeds the frozen bound before conversion THEN input SHALL be rejected" do
    input = %{
      alternative: [[9_007_199_254_740_993]],
      reference: [[0]],
      lower_bound: 0.0,
      upper_bound: 9_007_199_254_740_992.0
    }

    assert {:error, :out_of_range} = Compute.compare(input, %{confidence_level: 0.95})
  end

  test "NUM-06 WHEN finite outcome sums would overflow THEN normalized means SHALL stay finite" do
    input = %{
      alternative: List.duplicate(List.duplicate(1.0e308, 3), 3),
      reference: List.duplicate(List.duplicate(0.0, 3), 3),
      lower_bound: 0.0,
      upper_bound: 1.0e308
    }

    assert {:ok, result} = Compute.compare(input, %{confidence_level: 0.95})
    assert result.estimate == 1.0e308
    assert result.upper == 1.0e308
    assert result.lower <= result.estimate
    assert result.half_width <= 1.0e308
  end

  test "NUM-04 WHEN incompatible matching capitals give empty inversion THEN output SHALL be conservative" do
    alternative = for row <- 0..19, do: for(column <- 0..19, do: rem(row + column, 2) * 1.0)

    input = %{
      alternative: alternative,
      reference: List.duplicate(List.duplicate(0.5, 20), 20),
      lower_bound: 0.0,
      upper_bound: 1.0
    }

    assert {:ok, result} = Compute.compare(input, %{confidence_level: 0.95})
    assert result.lower == -1.0
    assert result.upper == 1.0
    assert result.p_value == 1.0
    assert result.warnings == [:empty_inversion]
    refute result.informative
  end
end
