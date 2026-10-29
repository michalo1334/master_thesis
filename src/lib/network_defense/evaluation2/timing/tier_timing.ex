defmodule NetworkDefense.Evaluation2.Timing.TierTiming do
  @moduledoc """
  Measured timing of one study tier.

  `plan_selection_us`, `simulation_us`, and `total_us` hold one elapsed value per
  measured replica, in measured position order. Warm-up stays outside the measured
  values. One clock owned by the Final collection phase takes every boundary, so
  queue and retry delay stay inside the measured interval.

  The tier names one network-size tier. Its order comes from the closed
  `NetworkDefense.Evaluation2.Tier` order, so no tier position is stored.
  """

  alias NetworkDefense.Evaluation2.Tier

  @type elapsed_us :: non_neg_integer()

  @type t :: %__MODULE__{
          tier: Tier.t(),
          plan_selection_us: [elapsed_us()],
          simulation_us: [elapsed_us()],
          total_us: [elapsed_us()]
        }

  defstruct [:tier, :plan_selection_us, :simulation_us, :total_us]
end
