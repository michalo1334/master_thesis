defmodule NetworkDefense.Evaluation2.Study.Final.CorrectedFamily.Comparison do
  @moduledoc false

  use Spectral

  # Statistics and family adjustment of one declared comparison.

  alias NetworkDefense.Evaluation2.Study.Result.Comparison.{Adjustment, Statistics}

  @type t :: %__MODULE__{
          statistics: Statistics.t(),
          adjustment: Adjustment.t()
        }

  defstruct [:statistics, :adjustment]
end
