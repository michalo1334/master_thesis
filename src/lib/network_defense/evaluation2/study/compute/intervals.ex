defmodule NetworkDefense.Evaluation2.Study.Compute.Intervals do
  @moduledoc false

  alias NetworkDefense.Evaluation2.Study.Compute.Betting

  @tolerance 1.0e-10
  @iterations 64

  @spec invert(map(), float()) :: {:ok, {float(), float()}} | :empty
  def invert(prepared, error) do
    threshold = :math.log(2 / error)
    lower = endpoint(prepared, threshold, :positive)
    upper = endpoint(prepared, threshold, :negative)
    if lower <= upper, do: {:ok, {lower, upper}}, else: :empty
  end

  defp endpoint(prepared, threshold, :positive) do
    {at_zero, _} = Betting.log_capitals(prepared, 0.0)
    {at_one, _} = Betting.log_capitals(prepared, 1.0)

    cond do
      at_zero <= threshold -> 0.0
      at_one > threshold -> 1.0
      true -> bisect(prepared, threshold, :positive, 0.0, 1.0, @iterations)
    end
  end

  defp endpoint(prepared, threshold, :negative) do
    {_, at_zero} = Betting.log_capitals(prepared, 0.0)
    {_, at_one} = Betting.log_capitals(prepared, 1.0)

    cond do
      at_one <= threshold -> 1.0
      at_zero > threshold -> 0.0
      true -> bisect(prepared, threshold, :negative, 0.0, 1.0, @iterations)
    end
  end

  defp bisect(_prepared, _threshold, direction, low, high, remaining)
       when high - low <= @tolerance or remaining == 0 do
    if direction == :positive, do: low, else: high
  end

  defp bisect(prepared, threshold, direction, low, high, remaining) do
    middle = (low + high) / 2
    {plus, minus} = Betting.log_capitals(prepared, middle)
    move_low? = if direction == :positive, do: plus > threshold, else: minus <= threshold

    if move_low? do
      bisect(prepared, threshold, direction, middle, high, remaining - 1)
    else
      bisect(prepared, threshold, direction, low, middle, remaining - 1)
    end
  end
end
