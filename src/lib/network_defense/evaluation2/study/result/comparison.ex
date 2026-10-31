defmodule NetworkDefense.Evaluation2.Study.Result.Comparison do
  @moduledoc """
  One corrected comparison of the study result.

  The comparison keeps its declared identity, matching-based bounded-mean
  statistics, and the Holm family adjustment.
  """

  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.Result.Comparison.{Adjustment, Statistics}

  @type t :: %__MODULE__{
          identity: Study.Comparison.t(),
          statistics: Statistics.t(),
          adjustment: Adjustment.t()
        }

  defstruct [:identity, :statistics, :adjustment]
end
