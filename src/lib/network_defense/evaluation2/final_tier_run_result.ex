defmodule NetworkDefense.Evaluation2.FinalTierRunResult do
  @moduledoc false

  # Combined result of one Final tier run.
  #
  # The runner joins the tier coordinate of the collection loop with the Gust run
  # identity and the timing that the coordinator measured for that run.
  # The value is transient.
  alias NetworkDefense.Evaluation2.Study.Result.Timing
  alias NetworkDefense.Evaluation2.Study.Tier

  @type t :: %__MODULE__{
          tier: Tier.t(),
          gust_run_id: pos_integer(),
          timing: Timing.Tier.t()
        }

  defstruct [:tier, :gust_run_id, :timing]
end
