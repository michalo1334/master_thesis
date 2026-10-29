defmodule NetworkDefense.Evaluation2.Study.Definition.Candidate do
  @moduledoc false

  @type t :: %__MODULE__{
          id: String.t(),
          plan_count_per_side: pos_integer(),
          attacks_per_plan: pos_integer()
        }
  defstruct [:id, :plan_count_per_side, :attacks_per_plan]
end
