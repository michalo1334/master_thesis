defmodule NetworkDefense.Evaluation2.FinalTierRunResult do
  @moduledoc """
  Combined result of one Final tier run.

  The runner joins the Gust run identity and its decoded terminal receipt with the
  timing that the coordinator measured for that run. The receipt names the
  network-size tier, and the replica equality gate reads only the receipts.
  """

  alias NetworkDefense.Evaluation2.Contracts.FinalTierContract
  alias NetworkDefense.Evaluation2.Timing.TierTiming

  @type t :: %__MODULE__{
          gust_run_id: pos_integer(),
          receipt: FinalTierContract.Output.t(),
          timing: TierTiming.t()
        }

  defstruct [:gust_run_id, :receipt, :timing]
end
