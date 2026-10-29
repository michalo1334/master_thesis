defmodule NetworkDefense.Evaluation2.CandidateAssessment do
  @moduledoc """
  Result of one candidate and comparison assessment.

  The assessment keeps the guarded half-width and the informativeness of the
  bounded precision estimate, plus the derived pass decision. It identifies its
  work by candidate and comparison position only.
  """

  @type t :: %__MODULE__{
          candidate_position: non_neg_integer(),
          comparison_position: non_neg_integer(),
          guarded_half_width: float(),
          informative: boolean(),
          passes: boolean()
        }

  defstruct [
    :candidate_position,
    :comparison_position,
    :guarded_half_width,
    :informative,
    :passes
  ]
end
