defmodule NetworkDefense.Evaluation2.Timing.TimingSummary do
  @moduledoc """
  Measured timing of one Final collection.

  The summary holds one tier entry per declared tier, in the closed
  `NetworkDefense.Evaluation2.Tier` order. The order follows the declared tiers,
  never map enumeration or completion order.
  """

  alias NetworkDefense.Evaluation2.Timing.TierTiming

  @type t :: %__MODULE__{tiers: [TierTiming.t()]}

  defstruct [:tiers]
end
