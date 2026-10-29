defmodule NetworkDefense.Evaluation2.Study.Result.Comparison do
  @moduledoc """
  One corrected comparison of the study result.

  The comparison keeps the declared identity, the typed statistics of the
  crossed bootstrap estimate, and the family adjustment. Fixed wire literals
  appear as atom types, and the Python wire shape stays at the transport
  boundary.
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
