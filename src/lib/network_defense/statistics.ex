defmodule NetworkDefense.Statistics do
  @moduledoc false

  def summary(values) do
    sorted = Enum.sort(values)
    n = length(sorted)

    if n == 0 do
      %{mean: 0.0, median: 0, p95: 0, p99: 0, min: 0, max: 0, variance: 0.0}
    else
      mean = Enum.sum(sorted) / n
      variance = Enum.reduce(sorted, 0.0, fn x, acc -> acc + (x - mean) * (x - mean) end) / n

      %{
        mean: mean,
        median: percentile(sorted, n, 0.5),
        p95: percentile(sorted, n, 0.95),
        p99: percentile(sorted, n, 0.99),
        min: List.first(sorted),
        max: Enum.max(sorted),
        variance: variance
      }
    end
  end

  defp percentile(sorted, n, p) when n > 0 do
    idx = max(0, Kernel.trunc(p * (n - 1)))
    Enum.at(sorted, idx)
  end
end
