defmodule NetworkDefense.Evaluation2.Study.Compute do
  @moduledoc """
  Pure fixed-sample matching-based bounded-mean inference.

  Independent IID row inputs and independent IID shared column inputs generate
  the crossed observations. The two input collections must also be independent.
  Counts and logical ordering are fixed before fresh Final observations.

  Betting follows the predictable bounded-mean principles in Waudby-Smith and
  Ramdas, *Estimating means of bounded random variables by betting*, JRSS B
  (2024), doi:10.1093/jrsssb/qkad009. Arithmetic e-value averaging follows Vovk
  and Wang, *E-values: Calibration, combination and applications*, Annals of
  Statistics (2021), doi:10.1214/20-AOS2020. The cyclic crossed-matching cover,
  past-only variance recipe and half-range caps form our declared adaptation.
  These citations do not establish published validation of the whole pipeline.

  Intervals have pointwise coverage under those assumptions. Holm controls the
  family test decisions; it does not make the intervals simultaneous.
  """

  alias NetworkDefense.Evaluation2.Study.Compute.{Betting, Holm, Input, Intervals, PilotPrecision}

  @doc "Analyze aligned crossed matrices using frozen model outcome bounds."
  @spec compare(map(), map()) :: {:ok, map()} | {:error, term()}
  def compare(input, %{confidence_level: confidence})
      when is_number(confidence) and confidence > 0 and confidence < 1 do
    with {:ok, prepared} <- Input.prepare(input) do
      {:ok, compare_prepared(prepared, 1 - confidence)}
    end
  end

  def compare(_input, _inference), do: {:error, :invalid_confidence_level}

  defp compare_prepared(%{range: range}, _error) when range == 0 do
    result(0.0, 0.0, 0.0, 1.0, [])
  end

  defp compare_prepared(%{matchings: xs, estimate: estimate, range: range}, error) do
    bets = Betting.prepare(xs, error)
    p_value = Betting.p_value(bets, estimate)

    case Intervals.invert(bets, error) do
      {:ok, {lower, upper}} ->
        low = min(range * (2 * lower - 1), estimate)
        high = max(range * (2 * upper - 1), estimate)
        result(estimate, low, high, p_value, [])

      :empty ->
        result(estimate, -range, range, 1.0, [:empty_inversion])
    end
  end

  defp result(estimate, lower, upper, p_value, warnings) do
    %{
      estimate: estimate,
      lower: lower,
      upper: upper,
      p_value: p_value,
      half_width: upper / 2 - lower / 2,
      informative: warnings == [],
      warnings: warnings
    }
  end

  @doc "Correct a canonical list of marginal p-values with Decimal Holm."
  @spec holm([number()], number()) :: [map()]
  def holm(p_values, alpha), do: Holm.correct(p_values, alpha)

  @doc """
  Assess interval sizes on outcome-independent Pilot subsets in outcome units.

  Pass the comparison's planning seed unchanged across candidate sizes.
  """
  @spec pilot_precision(map(), map(), map(), map(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def pilot_precision(input, sample_size, precision, inference, seed) do
    PilotPrecision.evaluate(input, sample_size, precision, inference, seed)
  end
end
