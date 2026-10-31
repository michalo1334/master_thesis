defmodule NetworkDefense.Evaluation2.Study.Definition.Comparison do
  @moduledoc false

  use Spectral

  alias NetworkDefense.Optimization.Contracts.OptimizationParams

  # One derived family comparison.
  #
  # Construction derives the membership and its canonical order from the tier
  # declarations. The group positions are global collection coordinates: they
  # count each tier/budget/strategy group once, including the CVSS reference
  # once per budget. Collection item positions remain local to their plan.

  @type t :: %__MODULE__{
          tier: String.t(),
          budget: pos_integer(),
          alternative: OptimizationParams.strategy(),
          reference: OptimizationParams.strategy(),
          outcome: String.t(),
          group_position: non_neg_integer(),
          reference_group_position: non_neg_integer()
        }
  defstruct [
    :tier,
    :budget,
    :alternative,
    :reference,
    :outcome,
    :group_position,
    :reference_group_position
  ]
end
