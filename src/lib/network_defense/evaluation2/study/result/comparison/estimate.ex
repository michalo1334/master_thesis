defmodule NetworkDefense.Evaluation2.Study.Result.Comparison.Estimate do
  @moduledoc """
  Estimated contrast of one comparison.

  The contrast is the alternative score minus the reference score.
  """

  use Spectral

  @typedoc "Direction of the estimated contrast."
  @type contrast :: :alternative_minus_reference

  @type t :: %__MODULE__{contrast: contrast(), value: float()}

  defstruct [:contrast, :value]
end
