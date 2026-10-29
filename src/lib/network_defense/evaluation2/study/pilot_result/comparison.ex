defmodule NetworkDefense.Evaluation2.Study.PilotResult.Comparison do
  @moduledoc """
  Assessment of one declared comparison for one Pilot candidate.

  The assessment keeps the guarded half-width of the bounded precision estimate,
  the informativeness of every outer subsample, and the derived pass decision.
  The identity is joined from the immutable definition by declared position.
  """

  alias NetworkDefense.Evaluation2.Study

  @type t :: %__MODULE__{
          identity: Study.Comparison.t(),
          guarded_half_width: float(),
          informative: boolean(),
          passes: boolean()
        }

  defstruct [:identity, :guarded_half_width, :informative, :passes]
end
