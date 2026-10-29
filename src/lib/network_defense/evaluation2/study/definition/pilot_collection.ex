defmodule NetworkDefense.Evaluation2.Study.Definition.PilotCollection do
  @moduledoc false

  use Spectral

  alias NetworkDefense.Evaluation2.Study.Definition.TierRoot

  @type t :: %__MODULE__{
          plan_count_per_side: pos_integer(),
          attacks_per_plan: pos_integer(),
          selection_seeds: [non_neg_integer()],
          roots: [TierRoot.t()]
        }
  defstruct [:plan_count_per_side, :attacks_per_plan, :selection_seeds, :roots]
end
