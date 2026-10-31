defmodule NetworkDefense.Evaluation2.Study.Result.Comparison.Statistics do
  @moduledoc """
  Typed statistics of one corrected comparison.

  The estimate, the interval, the test, and the assessment keep the scientific
  grouping of the comparison contract.
  """

  use Spectral

  alias NetworkDefense.Evaluation2.Study.Result.Comparison.{
    Assessment,
    Estimate,
    Interval,
    Test
  }

  @typedoc "Statistics method of the Final comparison."
  @type method :: :matching_bounded_mean_v1

  @type t :: %__MODULE__{
          method: method(),
          estimate: Estimate.t(),
          interval: Interval.t(),
          test: Test.t(),
          assessment: Assessment.t()
        }

  defstruct [:method, :estimate, :interval, :test, :assessment]
end
