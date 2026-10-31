defmodule NetworkDefense.Evaluation2.Study.Result.Comparison.Assessment do
  @moduledoc """
  Informativeness assessment of one comparison.

  Empty inversion returns the full known contrast range conservatively.
  """

  use Spectral

  @typedoc "Availability of an informative inversion."
  @type status :: :informative | :non_informative

  @typedoc "Warning raised by the comparison computation."
  @type warning :: :empty_inversion

  @type t :: %__MODULE__{
          status: status(),
          warnings: [warning()]
        }

  defstruct [:status, :warnings]
end
