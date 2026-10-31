defmodule NetworkDefense.Evaluation2.Compute.MatchingTest do
  @moduledoc """
  Fixed cyclic matching cover of the native numerical core.

  Cases: the cover half of NUM-01 (every cell appears exactly once, and every
  matching uses distinct row and column inputs) in both rectangular
  orientations, plus the fixed offset order of the audited method.
  """

  use ExUnit.Case, async: true
  @moduletag :unit

  alias NetworkDefense.Evaluation2.Study.Compute.Matching

  defp cells(cover), do: cover |> List.flatten() |> Enum.sort()

  defp all_cells(rows, columns),
    do: for(row <- 0..(rows - 1), column <- 0..(columns - 1), do: {row, column})

  defp assert_distinct_inputs(cover) do
    for matching <- cover do
      rows = matching |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
      columns = matching |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

      assert length(rows) == length(matching),
             "one matching repeats a row input: #{inspect(matching)}"

      assert length(columns) == length(matching),
             "one matching repeats a column input: #{inspect(matching)}"
    end
  end

  test "a wider matrix has one matching per column and one cell per row" do
    cover = Matching.coordinates(3, 5)

    assert Enum.count(cover) == 5
    assert Enum.all?(cover, &(Enum.count(&1) == 3))
    assert_distinct_inputs(cover)
    assert cells(cover) == all_cells(3, 5)
  end

  test "a taller matrix has one matching per row and one cell per column" do
    cover = Matching.coordinates(5, 3)

    assert Enum.count(cover) == 5
    assert Enum.all?(cover, &(Enum.count(&1) == 3))
    assert_distinct_inputs(cover)
    assert cells(cover) == all_cells(5, 3)
  end

  test "a square matrix keeps one full matching per offset" do
    cover = Matching.coordinates(4, 4)

    assert Enum.count(cover) == 4
    assert Enum.all?(cover, &(Enum.count(&1) == 4))
    assert cells(cover) == all_cells(4, 4)
  end

  test "a single row and a single column both stay covered" do
    assert Matching.coordinates(1, 3) == [[{0, 0}], [{0, 1}], [{0, 2}]]
    assert Matching.coordinates(3, 1) == [[{0, 0}], [{1, 0}], [{2, 0}]]
    assert Matching.coordinates(1, 1) == [[{0, 0}]]
  end

  test "matching content follows the fixed cyclic offsets" do
    assert Matching.coordinates(2, 3) == [
             [{0, 0}, {1, 1}],
             [{0, 1}, {1, 2}],
             [{0, 2}, {1, 0}]
           ]

    assert Matching.coordinates(3, 2) == [
             [{0, 0}, {1, 1}],
             [{1, 0}, {2, 1}],
             [{2, 0}, {0, 1}]
           ]
  end

  test "a square cover is a diagonal family" do
    assert Matching.coordinates(3, 3) == [
             [{0, 0}, {1, 1}, {2, 2}],
             [{0, 1}, {1, 2}, {2, 0}],
             [{0, 2}, {1, 0}, {2, 1}]
           ]
  end

  test "every cover covers each cell once for many shapes" do
    for rows <- 1..7, columns <- 1..7 do
      cover = Matching.coordinates(rows, columns)

      assert length(cover) == max(rows, columns)
      assert Enum.all?(cover, &(length(&1) == min(rows, columns)))
      assert cells(cover) == all_cells(rows, columns)
      assert_distinct_inputs(cover)
    end
  end

  test "coordinates are zero-based array positions" do
    assert Matching.coordinates(2, 2) |> List.flatten() == [{0, 0}, {1, 1}, {0, 1}, {1, 0}]
  end
end
