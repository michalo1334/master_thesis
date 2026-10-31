defmodule NetworkDefense.Evaluation2.Compute.InputTest do
  @moduledoc """
  Numerical boundary input of the native core.

  Cases: NUM-06 (finite frozen bounds, rectangular nonempty sides, out-of-range
  rejection, and explicit structural zero range), the input half of NUM-01
  (normalized matching tensor in the fixed cover order), and the input half of
  NUM-05 (repeatability and consistent rescaling).
  """

  use ExUnit.Case, async: true
  @moduletag :unit

  alias NetworkDefense.Evaluation2.Study.Compute.Input

  defp prepare(alternative, reference, lower_bound, upper_bound) do
    Input.prepare(%{
      alternative: alternative,
      reference: reference,
      lower_bound: lower_bound,
      upper_bound: upper_bound
    })
  end

  defp matchings!(result) do
    assert {:ok, %{matchings: matchings}} = result
    assert matchings != nil
    assert Nx.type(matchings) == {:f, 64}
    Nx.to_flat_list(matchings)
  end

  describe "NUM-06 accepted sides" do
    test "returns the normalized matching tensor, estimate, range, and dimensions" do
      assert {:ok, input} =
               prepare(
                 [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]],
                 [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]],
                 0.0,
                 6.0
               )

      assert Map.keys(input) |> Enum.sort() == [:columns, :estimate, :matchings, :range, :rows]
      assert input.rows == 2
      assert input.columns == 3
      assert input.range == 6.0
      assert input.estimate == 3.5
      assert Nx.shape(input.matchings) == {3, 2}

      # Cover order: matching 0 is the main diagonal, matching 2 wraps to column 0.
      expected = [7 / 12, 11 / 12, 8 / 12, 1.0, 9 / 12, 10 / 12]

      assert Enum.zip(Nx.to_flat_list(input.matchings), expected)
             |> Enum.all?(fn {actual, want} ->
               abs(actual - want) < 1.0e-12
             end)
    end

    test "a taller matrix keeps the matching count on the row side" do
      assert {:ok, input} =
               prepare([[8], [8], [8]], [[4], [4], [4]], 0.0, 8.0)

      assert input.rows == 3
      assert input.columns == 1
      assert Nx.shape(input.matchings) == {3, 1}
      assert Nx.to_flat_list(input.matchings) == [0.75, 0.75, 0.75]
      assert input.estimate == 4.0
    end

    test "accepts integer observations and integer bounds" do
      assert {:ok, input} = prepare([[2]], [[1]], 0, 8)
      assert input.range == 8.0
      assert input.estimate == 1.0
      assert Nx.to_flat_list(input.matchings) == [0.5625]
    end

    test "a single row and a single cell stay valid" do
      assert {:ok, single_row} = prepare([[1.0, 0.0]], [[0.0, 0.0]], 0.0, 1.0)
      assert Nx.shape(single_row.matchings) == {2, 1}
      assert Nx.to_flat_list(single_row.matchings) == [1.0, 0.5]
      assert single_row.estimate == 0.5

      assert {:ok, single_cell} = prepare([[3.0]], [[1.0]], 0.0, 4.0)
      assert Nx.shape(single_cell.matchings) == {1, 1}
      assert single_cell.estimate == 2.0
      assert Nx.to_flat_list(single_cell.matchings) == [0.75]
    end
  end

  describe "NUM-06 structural zero range" do
    test "equal bounds return no matching tensor and a zero estimate" do
      assert {:ok, input} = prepare([[2.5, 2.5], [2.5, 2.5]], [[2.5, 2.5], [2.5, 2.5]], 2.5, 2.5)

      assert input.matchings == nil
      assert input.estimate == 0.0
      assert input.range == 0.0
      assert input.rows == 2
      assert input.columns == 2
    end

    test "equal bounds still validate both sides" do
      assert {:error, :out_of_range} = prepare([[2.5]], [[3.5]], 2.5, 2.5)
      assert {:error, :shape_mismatch} = prepare([[2.5, 2.5]], [[2.5]], 2.5, 2.5)
    end
  end

  describe "NUM-06 rejection" do
    test "rejects an inverted or non-numeric bound pair" do
      assert {:error, :inverted_bounds} = prepare([[1.0]], [[0.0]], 5.0, 1.0)
      assert {:error, :invalid_bound} = prepare([[1.0]], [[0.0]], nil, 1.0)
      assert {:error, :invalid_bound} = prepare([[1.0]], [[0.0]], 0.0, "1")
    end

    test "rejects a bound or range that leaves the finite float64 domain" do
      huge = Integer.pow(10, 400)

      assert {:error, :non_finite_bound} = prepare([[1.0]], [[0.0]], -huge, 1.0)
      assert {:error, :non_finite_range} = prepare([[1.0]], [[0.0]], -1.0e308, 1.0e308)
    end

    test "rejects a non-list side, an empty side, and an empty row" do
      assert {:error, :invalid_side} = prepare(:not_a_matrix, [[0.0]], 0.0, 1.0)
      assert {:error, :invalid_side} = prepare([:not_a_row], [[0.0]], 0.0, 1.0)
      assert {:error, :empty_side} = prepare([], [], 0.0, 1.0)
      assert {:error, :empty_row} = prepare([[]], [[]], 0.0, 1.0)
    end

    test "rejects unequal row counts and ragged rows" do
      assert {:error, :shape_mismatch} = prepare([[1.0]], [[0.0], [0.0]], 0.0, 1.0)
      assert {:error, :shape_mismatch} = prepare([[1.0, 0.0]], [[0.0]], 0.0, 1.0)
      assert {:error, :non_rectangular} = prepare([[1.0], [0.0, 1.0]], [[0.0], [0.0]], 0.0, 1.0)
    end

    test "rejects non-numeric and out-of-range observations" do
      assert {:error, :non_numeric_observation} = prepare([["1.0"]], [[0.0]], 0.0, 1.0)
      assert {:error, :non_numeric_observation} = prepare([[nil]], [[0.0]], 0.0, 1.0)
      assert {:error, :out_of_range} = prepare([[1.5]], [[0.0]], 0.0, 1.0)
      assert {:error, :out_of_range} = prepare([[0.0]], [[-0.5]], 0.0, 1.0)

      assert {:error, :non_finite_observation} =
               prepare([[Integer.pow(10, 400)]], [[0.0]], 0.0, 1.0)
    end

    test "rejects a missing required key" do
      assert {:error, :invalid_input} =
               Input.prepare(%{alternative: [[1.0]], lower_bound: 0.0, upper_bound: 1.0})

      assert {:error, :invalid_input} = Input.prepare(%{alternative: [[1.0]], reference: [[0.0]]})
      assert {:error, :invalid_input} = Input.prepare([1.0])
      assert {:error, :invalid_input} = Input.prepare(nil)
    end

    test "ignores keys outside the declared input contract" do
      assert {:ok, %{rows: 1, columns: 1}} =
               Input.prepare(%{
                 alternative: [[1.0]],
                 reference: [[0.0]],
                 lower_bound: 0.0,
                 upper_bound: 1.0,
                 comparison: :unused
               })
    end
  end

  describe "NUM-01 normalization" do
    test "maps the known contrast range onto the unit interval" do
      assert {:ok, high} = prepare([[1.0]], [[0.0]], 0.0, 1.0)
      assert Nx.to_flat_list(high.matchings) == [1.0]

      assert {:ok, low} = prepare([[0.0]], [[1.0]], 0.0, 1.0)
      assert Nx.to_flat_list(low.matchings) == [0.0]

      assert {:ok, neutral} = prepare([[0.5]], [[0.5]], 0.0, 1.0)
      assert Nx.to_flat_list(neutral.matchings) == [0.5]
      assert neutral.estimate == 0.0
    end

    test "uses the declared bounds even when the sample is narrower" do
      assert {:ok, input} = prepare([[3.0, 1.0]], [[1.0, 1.0]], 0.0, 10.0)

      assert Enum.zip(Nx.to_flat_list(input.matchings), [0.6, 0.5])
             |> Enum.all?(fn {a, b} -> abs(a - b) < 1.0e-12 end)
    end
  end

  describe "NUM-05 repeatability and scaling" do
    test "repeated preparation of the same input agrees" do
      first = prepare([[1.0, 2.0], [3.0, 4.0]], [[0.0, 0.0], [0.0, 0.0]], 0.0, 4.0)
      second = prepare([[1.0, 2.0], [3.0, 4.0]], [[0.0, 0.0], [0.0, 0.0]], 0.0, 4.0)

      assert matchings!(first) == matchings!(second)
      assert {:ok, %{estimate: estimate}} = first
      assert {:ok, %{estimate: other_estimate}} = second
      assert estimate == other_estimate
    end

    test "a consistent rescale of differences and bounds preserves the normalized tensor" do
      base = prepare([[4.0, 0.0]], [[0.0, 0.0]], 0.0, 4.0)
      scaled = prepare([[8.0, 0.0]], [[0.0, 0.0]], 0.0, 8.0)

      assert matchings!(base) == matchings!(scaled)
      assert {:ok, %{estimate: 2.0}} = base
      assert {:ok, %{estimate: 4.0}} = scaled
    end
  end
end
