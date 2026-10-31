defmodule NetworkDefense.Evaluation2.Study.Matrix do
  @moduledoc false

  use Spectral

  # Plan-by-attack matrix of one comparison side.
  #
  # A matrix is a plain nested list: one row per selected plan, one column per
  # shared attack seed. The outer index is the row index.
  #
  # `take/3` produces the canonical leading capacity of a planned matrix.
  # `select/3` keeps explicit row and column indexes. Assembly constructs the
  # planned dimensions and the shared column list, so neither operation checks
  # rectangularity, alignment, or ranges.

  @typedoc "Position of one row or one column."
  @type index :: non_neg_integer()

  @typedoc "One observed value of one plan and one attack seed."
  @type value :: float()

  @typedoc "Values of one plan, one entry per shared attack seed."
  @type row :: [value()]

  @typedoc "Row count and column count of one matrix."
  @type dimensions :: {rows :: index(), columns :: index()}

  @typedoc "Plan rows in plan order."
  @type t :: [row()]

  @spec dimensions(t()) :: dimensions()
  def dimensions([]), do: {0, 0}
  def dimensions([first_row | _other_rows] = matrix), do: {length(matrix), length(first_row)}

  # Keep the leading rows and the leading columns.
  #
  # The result carries the canonical planned capacity of one matrix.
  @spec take(t(), rows :: index(), columns :: index()) :: t()
  def take(matrix, rows, columns) do
    matrix
    |> Enum.take(rows)
    |> Enum.map(&Enum.take(&1, columns))
  end

  # Keep explicit row indexes and explicit shared-column indexes.
  #
  # The caller passes the indexes of the rows and of the one attack-column list
  # that both sides share.
  @spec select(t(), [index()], [index()]) :: t()
  def select(matrix, row_indexes, column_indexes) do
    Enum.map(row_indexes, fn row_index ->
      row = Enum.at(matrix, row_index)
      Enum.map(column_indexes, &Enum.at(row, &1))
    end)
  end
end
