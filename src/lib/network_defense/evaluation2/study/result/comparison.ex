defmodule NetworkDefense.Evaluation2.Study.Result.Comparison do
  @moduledoc """
  One corrected comparison of the study result.

  The comparison keeps the declared identity, the typed statistics of the
  crossed bootstrap estimate, and the family adjustment. Fixed wire literals
  appear as atom types, and the Python wire shape stays at the transport
  boundary.
  """

  alias NetworkDefense.Evaluation2.Study

  @type t :: %__MODULE__{
          identity: Study.Comparison.t(),
          statistics: __MODULE__.Statistics.t(),
          adjustment: __MODULE__.Adjustment.t()
        }

  defstruct [:identity, :statistics, :adjustment]

  defmodule Estimate do
    @moduledoc """
    Estimated contrast of one comparison.

    The contrast is the alternative score minus the reference score.
    """

    @typedoc "Direction of the estimated contrast."
    @type contrast :: :alternative_minus_reference

    @type t :: %__MODULE__{contrast: contrast(), value: float()}

    defstruct [:contrast, :value]
  end

  defmodule Interval do
    @moduledoc """
    Confidence interval of one comparison estimate.
    """

    @type t :: %__MODULE__{
            confidence_level: float(),
            lower: float(),
            upper: float()
          }

    defstruct [:confidence_level, :lower, :upper]
  end

  defmodule Test do
    @moduledoc """
    Two-sided test of one comparison.
    """

    @typedoc "Test method of the comparison contract."
    @type method :: :centered_crossed_bootstrap

    @typedoc "Alternative hypothesis of the test."
    @type alternative :: :two_sided

    @type t :: %__MODULE__{
            method: method(),
            alternative: alternative(),
            raw_p_value: float()
          }

    defstruct [:method, :alternative, :raw_p_value]
  end

  defmodule Assessment do
    @moduledoc """
    Informativeness assessment of one comparison.

    A zero-width interval is the only warning of the current method.
    """

    @typedoc "Informativeness of the observed outer subsamples."
    @type status :: :informative | :non_informative

    @typedoc "Warning raised by the comparison computation."
    @type warning :: :zero_width_interval

    @type t :: %__MODULE__{
            status: status(),
            warnings: [warning()]
          }

    defstruct [:status, :warnings]
  end

  defmodule Statistics do
    @moduledoc """
    Typed statistics of one corrected comparison.

    The estimate, the interval, the test, and the assessment keep the scientific
    grouping of the comparison contract.
    """

    alias NetworkDefense.Evaluation2.Study.Result.Comparison.{
      Assessment,
      Estimate,
      Interval,
      Test
    }

    @typedoc "Statistics method of the Final comparison."
    @type method :: :corrected_crossed_bootstrap_v1

    @type t :: %__MODULE__{
            method: method(),
            estimate: Estimate.t(),
            interval: Interval.t(),
            test: Test.t(),
            assessment: Assessment.t()
          }

    defstruct [:method, :estimate, :interval, :test, :assessment]
  end

  defmodule Adjustment do
    @moduledoc """
    Family adjustment of one comparison.
    """

    @type t :: %__MODULE__{
            adjusted_p_value: float(),
            reject_null: boolean()
          }

    defstruct [:adjusted_p_value, :reject_null]
  end
end
