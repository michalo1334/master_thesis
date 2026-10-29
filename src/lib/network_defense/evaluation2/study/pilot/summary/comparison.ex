defmodule NetworkDefense.Evaluation2.Study.Pilot.Summary.Comparison do
  @moduledoc false

  # Comparison detail of one Pilot candidate summary.
  #
  # The entry keeps the guarded half-width, the informativeness of the bounded
  # precision estimate, and the derived pass decision. The declared comparison
  # identity stays in the immutable definition and is joined by position.

  @type t :: %__MODULE__{
          comparison_position: non_neg_integer(),
          guarded_half_width: float(),
          informative: boolean(),
          passes: boolean()
        }

  defstruct [:comparison_position, :guarded_half_width, :informative, :passes]
end
