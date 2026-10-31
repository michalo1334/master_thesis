defmodule NetworkDefense.Evaluation2.Study.Compute.PilotPrecision do
  @moduledoc """
  Outcome-independent Pilot subsets with shared candidate permutation prefixes.

  The finite-pool guard quantile is a planning heuristic. It does not guarantee
  precision on independent Final data. Selected indices return to logical order.
  """

  alias NetworkDefense.Evaluation2.Study.{Compute, Matrix, Randomness}
  alias NetworkDefense.Evaluation2.Study.Compute.Input
  alias Nx.Random

  @spec evaluate(map(), map(), map(), map(), non_neg_integer()) :: {:ok, map()} | {:error, term()}
  def evaluate(
        input,
        %{plans: _, attacks: _} = size,
        %{outer_subsamples: _, guard_quantile: _} = precision,
        inference,
        seed
      ) do
    with {:ok, prepared} <- Input.prepare(input),
         :ok <- validate(size, precision, prepared, seed) do
      indices =
        subsets(prepared.rows, prepared.columns, size, precision.outer_subsamples, seed)

      results =
        Enum.reduce_while(indices, {:ok, []}, &evaluate_subset(&1, &2, input, inference))

      summarize(results, precision.guard_quantile)
    end
  end

  def evaluate(_input, _size, _precision, _inference, _seed),
    do: {:error, :invalid_pilot_precision}

  defp evaluate_subset({rows, columns}, {:ok, values}, input, inference) do
    subset = %{
      input
      | alternative: Matrix.select(input.alternative, rows, columns),
        reference: Matrix.select(input.reference, rows, columns)
    }

    case Compute.compare(subset, inference) do
      {:ok, result} -> {:cont, {:ok, [result | values]}}
      error -> {:halt, error}
    end
  end

  defp summarize({:ok, results}, quantile) do
    widths = results |> Enum.reverse() |> Enum.map(& &1.half_width)

    {:ok,
     %{
       half_widths: widths,
       guarded_half_width: quantile(widths, quantile),
       informative: Enum.all?(results, & &1.informative)
     }}
  end

  defp summarize(error, _quantile), do: error

  @doc """
  Return aligned subsets using Nx Threefry keys.

  Pass the comparison's planning seed and reuse it across candidate sizes.
  This preserves the checked outer roots and shared permutation prefixes.
  """
  @spec subsets(pos_integer(), pos_integer(), map(), pos_integer(), non_neg_integer()) ::
          [{[non_neg_integer()], [non_neg_integer()]}]
  def subsets(rows, columns, size, count, seed) do
    for outer <- 0..(count - 1) do
      row_key = seed |> Randomness.root(["outer", outer, "rows"]) |> Random.key()
      column_key = seed |> Randomness.root(["outer", outer, "columns"]) |> Random.key()
      {row_order, _} = Random.shuffle(row_key, Nx.iota({rows}))
      {column_order, _} = Random.shuffle(column_key, Nx.iota({columns}))
      {prefix(row_order, size.plans), prefix(column_order, size.attacks)}
    end
  end

  defp prefix(order, count) do
    order |> Nx.to_flat_list() |> Enum.take(count) |> Enum.sort()
  end

  @doc "Linearly interpolate the empirical quantile of a nonempty sample."
  @spec quantile([number(), ...], number()) :: float()
  def quantile(values, probability) when probability >= 0 and probability <= 1 do
    sorted = Enum.sort(values)
    position = probability * (length(sorted) - 1)
    lower = floor(position)
    fraction = position - lower
    left = Enum.at(sorted, lower)
    right = Enum.at(sorted, min(lower + 1, length(sorted) - 1))
    left + fraction * (right - left)
  end

  defp validate(size, precision, input, seed) do
    valid? =
      is_integer(seed) and seed >= 0 and valid_size?(size, input) and valid_precision?(precision)

    if valid?, do: :ok, else: {:error, :invalid_pilot_precision}
  end

  defp valid_size?(size, input) do
    is_integer(size.plans) and size.plans > 0 and size.plans <= input.rows and
      is_integer(size.attacks) and size.attacks > 0 and size.attacks <= input.columns
  end

  defp valid_precision?(precision) do
    is_integer(precision.outer_subsamples) and precision.outer_subsamples > 0 and
      is_number(precision.guard_quantile) and precision.guard_quantile > 0 and
      precision.guard_quantile < 1
  end
end
