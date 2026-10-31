defmodule NetworkDefense.Evaluation2.Study.Compute.Input do
  @moduledoc false

  use Spectral

  # Numeric boundary input of one comparison.
  #
  # The caller builds this value from accepted evidence and the frozen model
  # outcome range. The kernel receives no Repo record, Gust handle, or seed.
  # Observations arrive as nested lists and leave as one float64 tensor, so the
  # arithmetic that follows stays in Nx.
  #
  # The returned map carries:
  #
  # - `matchings`: normalized contrast `X = (D / H + 1) / 2` in `[0, 1]` with
  #   `D` the cell contrast `alternative - reference`, shaped
  #   `{max(rows, columns), min(rows, columns)}` in the fixed matching order;
  # - `estimate`: all-cell mean contrast in outcome units;
  # - `range`: known model range `H = upper_bound - lower_bound`;
  # - `rows`, `columns`: plan-row and attack-column counts.
  #
  # A structural zero range (`H = 0`) states that every cell is a known zero
  # contrast. The value then reports `matchings: nil` and `estimate: 0.0`
  # instead of dividing by zero.
  #
  # Rejection reasons:
  #
  # - `:invalid_input` - the argument is not a map with the four required keys;
  # - `:invalid_bound` - one bound is not a number;
  # - `:non_finite_bound` - one bound leaves the finite float64 domain;
  # - `:inverted_bounds` - `lower_bound > upper_bound`;
  # - `:non_finite_range` - `upper_bound - lower_bound` leaves that domain;
  # - `:invalid_side` - a side is not a list of lists;
  # - `:empty_side` - a side has no plan row;
  # - `:empty_row` - a row carries no attack column;
  # - `:shape_mismatch` - the sides have different row counts;
  # - `:non_rectangular` - the rows of one side have different widths;
  # - `:non_numeric_observation` - a cell is not a number;
  # - `:non_finite_observation` - a cell leaves the finite float64 domain;
  # - `:out_of_range` - a cell lies outside `[lower_bound, upper_bound]`.
  #
  # A bounded contrast must keep both sides inside the frozen range, because the
  # method normalizes with that range and treats the outcome bounds as known
  # model facts rather than sample extremes. BEAM floats are finite, so
  # non-finite rejection applies to numbers that float64 cannot represent, such
  # as an integer above the finite double range.

  alias NetworkDefense.Evaluation2.Study.Compute.Matching

  @typedoc "Normalized matching tensor, or `nil` for a structural zero range."
  @type matchings :: Nx.Tensor.t() | nil

  @typedoc "Prepared numeric input of one comparison."
  @type t :: %{
          matchings: matchings(),
          estimate: float(),
          range: float(),
          rows: pos_integer(),
          columns: pos_integer()
        }

  @doc "Validate one comparison input and prepare its float64 matching tensor."
  @spec prepare(map()) :: {:ok, t()} | {:error, atom()}
  def prepare(%{
        alternative: alternative,
        reference: reference,
        lower_bound: lower_bound,
        upper_bound: upper_bound
      }) do
    with {:ok, lower, upper, range} <- bounds(lower_bound, upper_bound),
         {:ok, alternative, rows, columns} <- side(alternative, lower, upper),
         {:ok, reference} <- aligned_side(reference, lower, upper, rows, columns) do
      {:ok, assemble(alternative, reference, range, rows, columns)}
    end
  end

  def prepare(_input), do: {:error, :invalid_input}

  defp bounds(lower, upper) when is_number(lower) and is_number(upper) do
    with {:ok, lower} <- finite(lower),
         {:ok, upper} <- finite(upper) do
      ordered_bounds(lower, upper)
    else
      :error -> {:error, :non_finite_bound}
    end
  end

  defp bounds(_lower, _upper), do: {:error, :invalid_bound}

  defp ordered_bounds(lower, upper) when lower > upper, do: {:error, :inverted_bounds}

  defp ordered_bounds(lower, upper) do
    case spread(lower, upper) do
      {:ok, range} -> {:ok, lower, upper, range}
      :error -> {:error, :non_finite_range}
    end
  end

  defp spread(lower, upper) do
    {:ok, upper - lower}
  rescue
    ArithmeticError -> :error
  end

  defp side([], _lower, _upper), do: {:error, :empty_side}

  defp side(rows, lower, upper) when is_list(rows) do
    with {:ok, rows, columns} <- observations(rows, lower, upper) do
      {:ok, rows, length(rows), columns}
    end
  end

  defp side(_rows, _lower, _upper), do: {:error, :invalid_side}

  defp aligned_side(rows, lower, upper, expected_rows, expected_columns) do
    with {:ok, rows, row_count, column_count} <- side(rows, lower, upper) do
      if row_count == expected_rows and column_count == expected_columns do
        {:ok, rows}
      else
        {:error, :shape_mismatch}
      end
    end
  end

  defp observations(rows, lower, upper) do
    rows
    |> Enum.reduce_while({:ok, []}, fn row, {:ok, collected} ->
      case row_values(row, lower, upper) do
        {:ok, values} -> {:cont, {:ok, [values | collected]}}
        error -> {:halt, error}
      end
    end)
    |> rectangular()
  end

  defp rectangular({:ok, collected}) do
    collected = Enum.reverse(collected)

    case collected |> Enum.map(&length/1) |> Enum.uniq() do
      [columns] -> {:ok, collected, columns}
      _widths -> {:error, :non_rectangular}
    end
  end

  defp rectangular(error), do: error

  defp row_values(row, lower, upper) when is_list(row) and row != [] do
    row
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, collected} ->
      case observation(value, lower, upper) do
        {:ok, number} -> {:cont, {:ok, [number | collected]}}
        error -> {:halt, error}
      end
    end)
    |> restore_order()
  end

  defp row_values([], _lower, _upper), do: {:error, :empty_row}
  defp row_values(_row, _lower, _upper), do: {:error, :invalid_side}

  # Cells are collected in reverse order; the matching cover needs logical order.
  defp restore_order({:ok, collected}), do: {:ok, Enum.reverse(collected)}
  defp restore_order(error), do: error

  defp observation(value, lower, upper) when is_number(value) do
    case finite(value) do
      {:ok, number} ->
        if value < lower or value > upper, do: {:error, :out_of_range}, else: {:ok, number}

      :error ->
        {:error, :non_finite_observation}
    end
  end

  defp observation(_value, _lower, _upper), do: {:error, :non_numeric_observation}

  defp finite(value) when is_float(value), do: {:ok, value}

  defp finite(value) when is_integer(value) do
    {:ok, value * 1.0}
  rescue
    ArithmeticError -> :error
  end

  defp assemble(_alternative, _reference, range, rows, columns) when range == 0.0 do
    %{matchings: nil, estimate: 0.0, range: 0.0, rows: rows, columns: columns}
  end

  defp assemble(alternative, reference, range, rows, columns) do
    difference =
      Nx.subtract(Nx.tensor(alternative, type: :f64), Nx.tensor(reference, type: :f64))

    %{
      matchings: matchings(difference, range, rows, columns),
      estimate: estimate(difference, range),
      range: range,
      rows: rows,
      columns: columns
    }
  end

  defp matchings(difference, range, rows, columns) do
    indexes =
      rows
      |> Matching.coordinates(columns)
      |> Enum.map(fn matching ->
        Enum.map(matching, fn {row, column} -> row * columns + column end)
      end)

    difference
    |> Nx.divide(Nx.tensor(range, type: :f64))
    |> Nx.add(1.0)
    |> Nx.divide(2.0)
    |> Nx.reshape({rows * columns})
    |> Nx.take(Nx.tensor(indexes, type: :s64))
  end

  defp estimate(difference, range) do
    normalized =
      difference |> Nx.divide(Nx.tensor(range, type: :f64)) |> Nx.mean() |> Nx.to_number()

    value = normalized * range
    if value == 0.0, do: 0.0, else: value
  end
end
