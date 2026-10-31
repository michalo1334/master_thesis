defmodule NetworkDefense.Evaluation2Test.NumericAnchors do
  @moduledoc """
  Independent reference arithmetic for the matching-based bounded-mean method.

  Every function here is written from the documented rules in
  `docs/inprogress/evaluation2-statistical-validation.md` (observation model,
  selected capital recipe, inversion policy, Holm procedure) and from the
  matching cover in `docs/inprogress/evaluation2-refactor-sketches.md`.
  Nothing in this module calls the production kernel, so a comparison between
  the two is a real cross-check rather than a tautology.

  Plain sequential Elixir is deliberate: the reference stays small and
  readable instead of fast, and it shares no code with the Nx implementation.

  Conventions match the specification:

    * plan rows are the outer list, attack columns the inner list;
    * `h = upper_bound - lower_bound` is the known model range;
    * a cell contrast is normalized as `x = (d / h + 1) / 2`;
    * the tested null is "no effect", that is normalized mean one half;
    * both capital functions are inverted at `2 / confidence_error`.

  Capitals are kept in log space. Products over matchings then stay finite for
  long horizons, and the reference can express interval brackets and p-values
  without an intermediate overflow.
  """

  alias Decimal

  @smallest_normal 2.2250738585072014e-308
  @log_smallest_normal :math.log(@smallest_normal)
  @log_two :math.log(2.0)

  ## Matching cover

  @doc """
  Fixed cyclic matching cover of a `rows` by `columns` matrix.

  Returns one list per matching, each holding `{row, column}` zero-based
  coordinates, all distinct in both coordinates. With at most as many rows as
  columns the cover holds `columns` matchings of every row against
  `(row + t) mod columns`; otherwise it holds `rows` matchings of every column
  against `(column + t) mod rows`. Every cell appears exactly once.
  """
  def cover(rows, columns) when rows <= columns do
    for t <- 0..(columns - 1) do
      for i <- 0..(rows - 1), do: {i, rem(i + t, columns)}
    end
  end

  def cover(rows, columns) do
    for t <- 0..(rows - 1) do
      for j <- 0..(columns - 1), do: {rem(j + t, rows), j}
    end
  end

  @doc "All cells of `cover/2` in cover order."
  def covered_cells(rows, columns), do: cover(rows, columns) |> List.flatten()

  ## Capital arithmetic

  @doc """
  Log positive and log negative capital of one matching.

  `xs` are the normalized observations of the matching in logical order, `mu`
  the tested or inverted candidate mean, and `error` the confidence error. Each
  bet uses only earlier observations: the running mean starts at one half and
  the variance proxy at one quarter, and the squared error of an observation
  uses the mean before that observation.
  """
  def log_capitals(xs, mu, error) do
    size = length(xs)
    numerator = 2 * :math.log(2 / error)

    {log_positive, log_negative, _sum, _squared, _mean} =
      Enum.reduce(
        Enum.with_index(xs),
        {0.0, 0.0, 0.0, 0.0, 0.5},
        fn {x, index}, {log_pos, log_neg, sum, squared, mean} ->
          # `index` observations are past, so the proxy divides by index + 1.
          variance = (0.25 + squared) / (index + 1)
          bet = :math.sqrt(numerator / (size * variance))
          distance = x - mu

          positive = 1 + min(bet, positive_cap(mu)) * distance
          negative = 1 - min(bet, negative_cap(mu)) * distance

          {log_pos + :math.log(positive), log_neg + :math.log(negative), sum + x,
           squared + :math.pow(x - mean, 2), (0.5 + sum + x) / (index + 2)}
        end
      )

    {log_positive, log_negative}
  end

  defp positive_cap(mu) when mu == 0.0, do: :infinity
  defp positive_cap(mu), do: 0.5 / mu

  defp negative_cap(mu) when mu == 1.0, do: :infinity
  defp negative_cap(mu), do: 0.5 / (1 - mu)

  @doc """
  Log arithmetic mean capital of several matchings at candidate mean `mu`.

  Averaging happens on the capital scale, so the mean of the log capitals is
  not the answer; `log_mean/1` applies the log-sum-exp step instead.
  """
  def log_mean_capitals(matchings, mu, error) do
    matchings
    |> Enum.map(&log_capitals(&1, mu, error))
    |> Enum.unzip()
    |> then(fn {positives, negatives} -> {log_mean(positives), log_mean(negatives)} end)
  end

  @doc "Capital-scale arithmetic mean from log capitals."
  def log_mean(logs) do
    maximum = Enum.max(logs)

    maximum + :math.log(Enum.sum(Enum.map(logs, fn log -> :math.exp(log - maximum) end))) -
      :math.log(length(logs))
  end

  @doc "Marginal two-sided p-value of an all-cell estimate at the zero-effect null."
  def p_value(matchings, estimate, error) do
    if estimate == 0.0 do
      1.0
    else
      {positive, negative} = log_mean_capitals(matchings, 0.5, error)
      selected = if estimate > 0, do: positive, else: negative
      bounded_p(selected)
    end
  end

  @doc """
  Conservative interval of the true mean in contrast units.

  Inverts the decreasing positive capital for the lower endpoint and the
  increasing negative capital for the upper endpoint, enlarges to contain the
  point estimate, and intersects with the known contrast range `[-range,
  range]`. An endpoint that leaves the normalized candidate domain is clipped
  to the domain edge instead of being reported as a failed inversion.
  """
  def interval(matchings, estimate, range, error) do
    log_threshold = :math.log(2 / error)

    {:ok, lower_mean} =
      bisect(&positive_log_capital(&1, matchings, error), log_threshold, :decreasing)

    {:ok, upper_mean} =
      bisect(&negative_log_capital(&1, matchings, error), log_threshold, :increasing)

    lower = range * (2 * lower_mean - 1)
    upper = range * (2 * upper_mean - 1)
    {:ok, {max(min(lower, estimate), -range), min(max(upper, estimate), range)}}
  end

  defp positive_log_capital(mu, matchings, error) do
    matchings |> log_mean_capitals(mu, error) |> elem(0)
  end

  defp negative_log_capital(mu, matchings, error) do
    matchings |> log_mean_capitals(mu, error) |> elem(1)
  end

  defp bisect(fun, threshold, direction) do
    case bracket(fun, threshold, direction) do
      {:clip, endpoint} -> {:ok, endpoint}
      :search -> bisect_steps(fun, threshold, direction, 0.0, 1.0, 64)
    end
  end

  # An endpoint outside the normalized candidate domain clips to the domain
  # edge; otherwise the crossing lies inside the domain and needs bisection.
  defp bracket(fun, threshold, :decreasing) do
    cond do
      fun.(0.0) < threshold -> {:clip, 0.0}
      fun.(1.0) >= threshold -> {:clip, 1.0}
      true -> :search
    end
  end

  defp bracket(fun, threshold, :increasing) do
    cond do
      fun.(1.0) < threshold -> {:clip, 1.0}
      fun.(0.0) >= threshold -> {:clip, 0.0}
      true -> :search
    end
  end

  defp bisect_steps(_fun, _threshold, _direction, low, _high, 0), do: {:ok, low}

  defp bisect_steps(fun, threshold, direction, low, high, steps) do
    middle = (low + high) / 2

    {low, high} =
      case {fun.(middle), direction} do
        {value, :decreasing} when value >= threshold -> {middle, high}
        {_value, :decreasing} -> {low, middle}
        {value, :increasing} when value <= threshold -> {middle, high}
        {_value, :increasing} -> {low, middle}
      end

    if high - low <= 1.0e-13,
      do: {:ok, if(direction == :decreasing, do: low, else: high)},
      else: bisect_steps(fun, threshold, direction, low, high, steps - 1)
  end

  defp bounded_p(log_capital) do
    log_p = @log_two - log_capital

    cond do
      log_p >= 0.0 -> 1.0
      log_p < @log_smallest_normal -> @smallest_normal
      true -> :math.exp(log_p)
    end
  end

  ## Whole-comparison reference

  @doc """
  Full reference analysis of one comparison.

  Returns the all-cell estimate, the marginal p-value at the zero-effect null,
  the conservative interval, and that interval's half-width.
  """
  def reference_compare(alternative, reference, lower_bound, upper_bound, confidence_level) do
    range = upper_bound - lower_bound
    estimate = mean_contrast(alternative, reference)

    if range == 0.0 do
      %{estimate: 0.0, lower: 0.0, upper: 0.0, p_value: 1.0, half_width: 0.0}
    else
      matchings = normalized_matchings(alternative, reference, range)
      error = 1 - confidence_level
      p_value = p_value(matchings, estimate, error)
      {:ok, {lower, upper}} = interval(matchings, estimate, range, error)

      %{
        estimate: estimate,
        lower: lower,
        upper: upper,
        p_value: p_value,
        half_width: upper / 2 - lower / 2
      }
    end
  end

  @doc "All-cell mean contrast of two aligned matrices."
  def mean_contrast(alternative, reference) do
    alternative
    |> Enum.zip(reference)
    |> Enum.flat_map(fn {a_row, r_row} -> Enum.zip_with(a_row, r_row, &(&1 - &2)) end)
    |> mean()
  end

  defp normalized_matchings(alternative, reference, range) do
    contrasts = contrast_rows(alternative, reference)

    cover(length(contrasts), length(hd(contrasts)))
    |> Enum.map(fn matching ->
      Enum.map(matching, fn {i, j} ->
        (Enum.at(Enum.at(contrasts, i), j) / range + 1) / 2
      end)
    end)
  end

  defp contrast_rows(alternative, reference) do
    alternative
    |> Enum.zip(reference)
    |> Enum.map(fn {a_row, r_row} -> Enum.zip_with(a_row, r_row, &(&1 - &2)) end)
  end

  @doc """
  Reference analysis of a constant cell contrast.

  Constant contrasts make every matching stream identical, so the averaged
  capital equals one matching capital and one sequential pass suffices.
  `pairs` is the matching horizon, that is `min(rows, columns)`.
  """
  def constant_contrast(contrast, range, pairs, confidence_level) do
    xs = List.duplicate((contrast / range + 1) / 2, pairs)
    matchings = [xs]
    error = 1 - confidence_level

    %{
      p_value: p_value(matchings, contrast, error),
      log_capitals: log_mean_capitals(matchings, 0.5, error)
    }
    |> Map.merge(
      case interval(matchings, contrast, range, error) do
        {:ok, {lower, upper}} -> %{lower: lower, upper: upper, half_width: upper / 2 - lower / 2}
      end
    )
  end

  @doc """
  Log capitals of a constant-contrast matching at candidate mean `mu`.

  A test uses this to check that a reported endpoint lies on the conservative
  side of the documented `2 / error` threshold.
  """
  def constant_log_capitals(value, pairs, confidence_error, mu) do
    log_capitals(List.duplicate(value, pairs), mu, confidence_error)
  end

  ## Holm

  @doc """
  Exact Holm correction, the oracle for the kernel's decimal Holm.

  Raw p-values enter as float64 values converted to their exact decimal value.
  The tests use binary-exact p-values only (multiples of a negative power of
  two), where every conversion convention agrees. Adjustments are capped at
  one, monotone under the running maximum, and decided inclusively.
  """
  def holm(p_values, alpha) do
    alpha = decimal(alpha)
    family = length(p_values)

    adjusted =
      p_values
      |> Enum.with_index()
      |> Enum.sort()
      |> Enum.with_index(1)
      |> Enum.map_reduce(Decimal.new(0), fn {{p, canonical}, position}, running ->
        step =
          p
          |> decimal()
          |> Decimal.mult(Decimal.new(family - position + 1))
          |> Decimal.min(Decimal.new(1))

        next = Decimal.max(running, step)
        {{canonical, p, next}, next}
      end)
      |> elem(0)
      |> Map.new(fn {canonical, p, adjustment} ->
        reject? = Decimal.compare(adjustment, alpha) != :gt
        {canonical, %{p_value: p, adjusted_p_value: adjustment, reject?: reject?}}
      end)

    Enum.map(0..(family - 1), &Map.fetch!(adjusted, &1))
  end

  defp decimal(%Decimal{} = value), do: value
  defp decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp decimal(value), do: Decimal.new(value)

  ## Quantiles

  @doc """
  Guard quantile with linear interpolation (Hyndman-Fan type 7).

  Interpolates between the two neighbouring order statistics, so a quantile
  between observed widths never leaves the observed range.
  """
  def quantile([], _q), do: nil

  def quantile(values, q) do
    sorted = Enum.sort(values)
    rank = (length(sorted) - 1) * q
    low = trunc(rank)
    fraction = rank - low
    lower = Enum.at(sorted, low)
    upper = Enum.at(sorted, min(low + 1, length(sorted) - 1))
    lower + (upper - lower) * fraction
  end

  ## Helpers

  @doc "Arithmetic mean of a non-empty list of numbers."
  def mean([_ | _] = values), do: Enum.sum(values) / length(values)

  @doc "Deterministic matrix from a closed-form rule, so fixtures need no RNG."
  def build(rows, columns, fun) do
    for i <- 0..(rows - 1), do: for(j <- 0..(columns - 1), do: fun.(i, j))
  end
end
