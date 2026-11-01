defmodule NetworkDefense.Evaluation2.Study.Compute.Kernel do
  @moduledoc false

  import Nx.Defn

  # Fuse repeated capital evaluations on CPU. The method and conservative outer
  # brackets are unchanged; compilation removes eager tensor dispatch overhead.
  defn analyze(observations, error) do
    {observations, bets} = prepare(observations, error)
    {lower, upper} = invert(observations, bets, error)
    {plus, minus} = log_capitals(observations, bets, 0.5)
    {lower, upper, plus, minus}
  end

  defn invert(observations, bets, error) do
    threshold = Nx.log(2.0 / error)
    {at_zero_plus, at_zero_minus} = log_capitals(observations, bets, 0.0)
    {at_one_plus, at_one_minus} = log_capitals(observations, bets, 1.0)

    {_, lower_low, _, _, upper_high, _, _, _} =
      while {iteration = 0, lower_low = Nx.tensor(0.0, type: :f64),
             lower_high = Nx.tensor(1.0, type: :f64), upper_low = Nx.tensor(0.0, type: :f64),
             upper_high = Nx.tensor(1.0, type: :f64), observations, bets, threshold},
            iteration < 34 do
        lower_middle = (lower_low + lower_high) / 2.0
        upper_middle = (upper_low + upper_high) / 2.0
        {lower_capital, _} = log_capitals(observations, bets, lower_middle)
        {_, upper_capital} = log_capitals(observations, bets, upper_middle)
        lower_moves = lower_capital > threshold
        upper_moves = upper_capital <= threshold

        {iteration + 1, Nx.select(lower_moves, lower_middle, lower_low),
         Nx.select(lower_moves, lower_high, lower_middle),
         Nx.select(upper_moves, upper_middle, upper_low),
         Nx.select(upper_moves, upper_high, upper_middle), observations, bets, threshold}
      end

    lower =
      Nx.select(
        at_zero_plus <= threshold,
        0.0,
        Nx.select(at_one_plus > threshold, 1.0, lower_low)
      )

    upper =
      Nx.select(
        at_one_minus <= threshold,
        1.0,
        Nx.select(at_zero_minus > threshold, 0.0, upper_high)
      )

    {lower, upper}
  end

  defn prepare(observations, error) do
    size = Nx.axis_size(observations, 1)
    prior_sum = Nx.cumulative_sum(observations, axis: 1) - observations
    counts = Nx.iota({1, size}, type: :f64)
    means = (prior_sum + 0.5) / (counts + 1.0)
    errors = Nx.pow(observations - means, 2)
    prior_errors = Nx.cumulative_sum(errors, axis: 1) - errors
    variances = (prior_errors + 0.25) / (counts + 1.0)
    bets = Nx.sqrt(2.0 * Nx.log(2.0 / error) / (size * variances))
    {observations, bets}
  end

  defn log_capitals(observations, bets, mean) do
    positive = Nx.min(bets, 0.5 / Nx.select(mean == 0.0, 1.0, mean))
    positive = Nx.select(mean == 0.0, bets, positive)
    negative = Nx.min(bets, 0.5 / Nx.select(mean == 1.0, 1.0, 1.0 - mean))
    negative = Nx.select(mean == 1.0, bets, negative)
    centered = observations - mean
    plus = Nx.sum(Nx.log(1.0 + positive * centered), axes: [1])
    minus = Nx.sum(Nx.log(1.0 - negative * centered), axes: [1])
    {log_average(plus), log_average(minus)}
  end

  defnp log_average(logs) do
    maximum = Nx.reduce_max(logs)
    maximum + Nx.log(Nx.sum(Nx.exp(logs - maximum)) / Nx.size(logs))
  end
end
