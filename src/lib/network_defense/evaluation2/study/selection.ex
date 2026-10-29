defmodule NetworkDefense.Evaluation2.Study.Selection do
  @moduledoc """
  Frozen Final sample-size selection.

  Resume writes the selection once from the accepted Pilot outcome, and every
  Final tier run reads the stored value. The selection holds no override flag:
  the accepted Pilot outcome states whether the selection overrides an
  insufficient result.
  """

  alias NetworkDefense.Evaluation2.Study

  @type t :: %__MODULE__{
          candidate_id: Study.candidate_id(),
          plan_count_per_side: pos_integer(),
          attacks_per_plan: pos_integer()
        }

  defstruct [:candidate_id, :plan_count_per_side, :attacks_per_plan]
end
