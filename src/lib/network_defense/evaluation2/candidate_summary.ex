defmodule NetworkDefense.Evaluation2.CandidateSummary do
  @moduledoc """
  Aggregated Pilot summary of one candidate.

  One summary collects every declared comparison of the candidate: the worst
  guarded half-width, the informativeness positions, the pass decision, and the
  predicted Final runtime that ranks the candidate. Non-informative positions
  stay visible even when the candidate is not recommended.

  The candidate identifier names a sample-size choice of the Pilot grid and is not
  a network-size tier.
  """

  alias NetworkDefense.Evaluation2.PilotOutcome

  @type t :: %__MODULE__{
          candidate_position: non_neg_integer(),
          candidate_id: PilotOutcome.candidate_id(),
          plan_count_per_side: pos_integer(),
          attacks_per_plan: pos_integer(),
          worst_guarded_half_width: float(),
          all_comparisons_informative: boolean(),
          non_informative_comparison_positions: [non_neg_integer()],
          all_comparisons_passed: boolean(),
          predicted_runtime_ms: number()
        }

  defstruct [
    :candidate_position,
    :candidate_id,
    :plan_count_per_side,
    :attacks_per_plan,
    :worst_guarded_half_width,
    :all_comparisons_informative,
    :non_informative_comparison_positions,
    :all_comparisons_passed,
    :predicted_runtime_ms
  ]
end
