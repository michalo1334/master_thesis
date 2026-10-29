defmodule NetworkDefense.Evaluation2.CorrectedFamily do
  @moduledoc """
  Corrected comparison family of one Final analysis.

  The corrected family keeps the declared family order and adds one adjustment per
  declared comparison. Every comparison identity carries the network-size tier, so
  tier order comes from `NetworkDefense.Evaluation2.Tier` and no tier position is
  stored.
  """

  alias NetworkDefense.Evaluation2.CorrectedFamily.Comparison

  @type t :: %__MODULE__{
          family_id: String.t(),
          method: String.t(),
          alpha: float(),
          family_size: pos_integer(),
          comparisons: [Comparison.t()]
        }

  defstruct [:family_id, :method, :alpha, :family_size, :comparisons]

  defmodule Comparison do
    @moduledoc "One corrected comparison of the declared family."

    alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonStatistics
    alias NetworkDefense.Evaluation.Family.Contracts.Adjustment
    alias NetworkDefense.Evaluation2.ComparisonIdentity

    @type t :: %__MODULE__{
            identity: ComparisonIdentity.t(),
            statistics: ComparisonStatistics.t(),
            adjustment: Adjustment.t()
          }

    defstruct [:identity, :statistics, :adjustment]
  end
end
