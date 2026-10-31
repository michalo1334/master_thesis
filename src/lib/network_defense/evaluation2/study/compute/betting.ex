defmodule NetworkDefense.Evaluation2.Study.Compute.Betting do
  @moduledoc """
  Fixed-sample, past-only bounded-mean betting on fixed matchings.

  Each matching has its own history. Arithmetic capital averages remain valid
  with dependent matchings. These averages are not an anytime-valid process.
  """

  @smallest_normal 2.2250738585072014e-308
  @log_smallest_normal :math.log(@smallest_normal)

  @doc "Calculate the sign-conservative two-sided p-value in log space."
  @spec p_value(map(), number()) :: float()
  def p_value(_prepared, estimate) when estimate == 0, do: 1.0

  def p_value(prepared, estimate) do
    {plus, minus} = log_capitals(prepared, 0.5)
    selected = if estimate > 0, do: plus, else: minus
    log_p = min(0.0, :math.log(2.0) - selected)
    if log_p < @log_smallest_normal, do: @smallest_normal, else: :math.exp(log_p)
  end

  @doc "Prepare past-only base bets at the shared confidence error."
  @spec prepare(Nx.Tensor.t(), float()) :: %{observations: Nx.Tensor.t(), bets: Nx.Tensor.t()}
  def prepare(matchings, error) do
    {_count, size} = Nx.shape(matchings)
    prior_sum = Nx.subtract(Nx.cumulative_sum(matchings, axis: 1), matchings)
    counts = Nx.iota({1, size}, type: :f64)
    means = Nx.divide(Nx.add(prior_sum, 0.5), Nx.add(counts, 1))
    errors = Nx.pow(Nx.subtract(matchings, means), 2)
    prior_errors = Nx.subtract(Nx.cumulative_sum(errors, axis: 1), errors)
    variances = Nx.divide(Nx.add(prior_errors, 0.25), Nx.add(counts, 1))
    tuning = Nx.tensor(2 * :math.log(2 / error), type: :f64)
    bets = Nx.sqrt(Nx.divide(tuning, Nx.multiply(size, variances)))
    %{observations: matchings, bets: bets}
  end

  @doc "Return logs of the separate arithmetic positive and negative averages."
  @spec log_capitals(map(), float()) :: {float(), float()}
  def log_capitals(%{observations: xs, bets: bets}, mean) do
    positive = if mean == 0.0, do: bets, else: Nx.min(bets, Nx.tensor(0.5 / mean, type: :f64))

    negative =
      if mean == 1.0, do: bets, else: Nx.min(bets, Nx.tensor(0.5 / (1 - mean), type: :f64))

    centered = Nx.subtract(xs, Nx.tensor(mean, type: :f64))

    plus =
      centered
      |> Nx.multiply(positive)
      |> Nx.add(1)
      |> Nx.log()
      |> Nx.sum(axes: [1])
      |> log_average()

    minus =
      centered
      |> Nx.multiply(negative)
      |> Nx.negate()
      |> Nx.add(1)
      |> Nx.log()
      |> Nx.sum(axes: [1])
      |> log_average()

    {plus, minus}
  end

  defp log_average(logs) do
    maximum = logs |> Nx.reduce_max() |> Nx.to_number()

    total =
      logs
      |> Nx.subtract(Nx.tensor(maximum, type: :f64))
      |> Nx.exp()
      |> Nx.sum()
      |> Nx.to_number()

    maximum + :math.log(total / Nx.size(logs))
  end
end
