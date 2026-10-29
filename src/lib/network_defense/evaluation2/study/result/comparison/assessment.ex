defmodule NetworkDefense.Evaluation2.Study.Result.Comparison.Assessment do
  @moduledoc """
  Informativeness assessment of one comparison.

  A zero-width interval is the only warning of the current method.
  """

  use Spectral

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
