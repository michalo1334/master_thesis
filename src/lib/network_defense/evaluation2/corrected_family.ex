defmodule NetworkDefense.Evaluation2.CorrectedFamily do
  @moduledoc false

  # Corrected Final comparison results in declared family order.
  #
  # The Final analysis owns these comparison outputs. The envelope of the
  # reported family (identifier, method, alpha) stays in the immutable definition
  # and is joined when the supported result view is built.

  @type t :: %__MODULE__{comparisons: [__MODULE__.Comparison.t()]}

  defstruct [:comparisons]

  defmodule Comparison do
    @moduledoc false

    # Statistics and family adjustment of one declared comparison.

    alias NetworkDefense.Evaluation2.Study.Result.Comparison.{Adjustment, Statistics}

    @type t :: %__MODULE__{
            statistics: Statistics.t(),
            adjustment: Adjustment.t()
          }

    defstruct [:statistics, :adjustment]
  end
end
