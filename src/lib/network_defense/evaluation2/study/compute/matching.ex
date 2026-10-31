defmodule NetworkDefense.Evaluation2.Study.Compute.Matching do
  @moduledoc false

  use Spectral

  # Fixed cyclic matching cover of one contrast matrix.
  #
  # One matching holds cells with distinct plan rows and distinct attack columns,
  # so its observations are independent under the declared product-input model.
  # Every cell appears in exactly one matching. Different matchings remain
  # dependent because they reuse row and column inputs.
  #
  # Coordinates are zero-based logical array positions in collected order. The
  # cover never depends on observed values. Positions follow the audited method:
  #
  # - wider matrix (`rows <= columns`): `columns` matchings of `rows` cells,
  #   cell `i` of matching `t` is `{i, (i + t) mod columns}`;
  # - taller matrix: `rows` matchings of `columns` cells, cell `j` of matching
  #   `t` is `{(j + t) mod rows, j}`.
  #
  # A wider matrix therefore has `max(rows, columns)` matchings of
  # `min(rows, columns)` cells, which is the shape of the normalized tensor.

  @typedoc "Zero-based position of one cell: one plan row and one attack column."
  @type coordinate :: {non_neg_integer(), non_neg_integer()}

  @typedoc "Cells that use distinct row inputs and distinct column inputs."
  @type matching :: [coordinate()]

  @typedoc "Complete cover of one matrix in fixed matching order."
  @type cover :: [matching()]

  @doc "Return the fixed cyclic cover of a `rows`-by-`columns` matrix."
  @spec coordinates(pos_integer(), pos_integer()) :: cover()
  def coordinates(rows, columns)
      when is_integer(rows) and rows > 0 and is_integer(columns) and columns > 0 and
             rows <= columns do
    for offset <- 0..(columns - 1),
        do: for(row <- 0..(rows - 1), do: {row, rem(row + offset, columns)})
  end

  def coordinates(rows, columns)
      when is_integer(rows) and rows > 0 and is_integer(columns) and columns > 0 do
    for offset <- 0..(rows - 1),
        do: for(column <- 0..(columns - 1), do: {rem(column + offset, rows), column})
  end
end
