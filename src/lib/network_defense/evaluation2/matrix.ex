defmodule NetworkDefense.Evaluation2.Matrix do
  @moduledoc """
  Plan-by-attack matrix of one comparison side.

  A matrix is a plain nested list: one row per selected plan, one column per
  shared attack seed. The outer index is the row index.

  `take/3` produces the canonical leading capacity of a planned matrix.
  `select/3` keeps explicit row and column indexes. Assembly constructs the
  planned dimensions and the shared column list, so neither operation checks
  rectangularity, alignment, or ranges.
  """

  alias NetworkDefense.Evaluation2.NotImplementedError

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

  @doc "Return the row count and the column count of one matrix."
  @spec dimensions(t()) :: dimensions()
  def dimensions(_matrix), do: raise(NotImplementedError, function: :dimensions)

  @doc """
  Keep the leading rows and the leading columns.

  The result carries the canonical planned capacity of one matrix.
  """
  @spec take(t(), rows :: index(), columns :: index()) :: t()
  def take(_matrix, _rows, _columns), do: raise(NotImplementedError, function: :take)

  @doc """
  Keep explicit row indexes and explicit shared-column indexes.

  The caller passes the indexes of the rows and of the one attack-column list that
  both sides share.
  """
  @spec select(t(), [index()], [index()]) :: t()
  def select(_matrix, _rows, _columns), do: raise(NotImplementedError, function: :select)
end
