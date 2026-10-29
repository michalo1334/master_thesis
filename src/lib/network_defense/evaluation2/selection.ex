defmodule NetworkDefense.Evaluation2.Selection do
  @moduledoc """
  Final selection frozen at the approval boundary.

  The selection names the declared candidate and the two sample counts that Final
  collection must reproduce. Resume writes it once, and every Final tier run reads
  that stored value instead of a caller argument.
  """

  alias NetworkDefense.Evaluation2.PilotOutcome

  @type t :: %__MODULE__{
          candidate_id: PilotOutcome.candidate_id(),
          plan_count_per_side: pos_integer(),
          attacks_per_plan: pos_integer(),
          pilot_override: boolean()
        }

  defstruct [:candidate_id, :plan_count_per_side, :attacks_per_plan, :pilot_override]
end
