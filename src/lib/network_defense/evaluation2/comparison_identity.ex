defmodule NetworkDefense.Evaluation2.ComparisonIdentity do
  @moduledoc """
  Stable identity of one declared family comparison.

  The identity names the network-size tier, the budget, both strategies, and the
  outcome. Tier order comes from `NetworkDefense.Evaluation2.Tier`, so the identity
  stores no tier position.
  """

  alias NetworkDefense.Evaluation2.Tier
  alias NetworkDefense.Optimization.Contracts.OptimizationParams

  @type t :: %__MODULE__{
          tier: Tier.t(),
          budget: pos_integer(),
          alternative: OptimizationParams.strategy(),
          reference: OptimizationParams.strategy(),
          outcome: String.t()
        }

  defstruct [:tier, :budget, :alternative, :reference, :outcome]
end
