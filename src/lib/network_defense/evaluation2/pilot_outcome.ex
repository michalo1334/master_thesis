defmodule NetworkDefense.Evaluation2.PilotOutcome do
  @moduledoc """
  Compact Pilot outcome stored on the execution.

  The outcome records the Pilot decision and, for a recommendation, the declared
  candidate with the two sample counts that Final collection must use. Complete
  candidate summaries stay in the terminal Pilot analysis result.
  """

  @typedoc """
  Identifier of one declared Pilot candidate.

  The identifier names a sample-size choice of the Pilot candidate grid. It is a
  plain candidate identifier and not a network-size tier.
  """
  @type candidate_id :: String.t()

  @type outcome :: :recommended | :insufficient

  @type t :: %__MODULE__{
          outcome: outcome(),
          candidate_id: candidate_id() | nil,
          plan_count_per_side: pos_integer() | nil,
          attacks_per_plan: pos_integer() | nil
        }

  defstruct [:outcome, :candidate_id, :plan_count_per_side, :attacks_per_plan]
end
