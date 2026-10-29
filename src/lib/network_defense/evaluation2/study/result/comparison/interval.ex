defmodule NetworkDefense.Evaluation2.Study.Result.Comparison.Interval do
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
