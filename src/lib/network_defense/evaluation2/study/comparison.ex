defmodule NetworkDefense.Evaluation2.Study.Comparison do
  @moduledoc """
  Declared identity of one family comparison.

  The identity names the network-size tier, the budget, both strategies, and the
  measured outcome. Pilot and Final result views share this type, and both join
  it from the immutable definition by declared position. Evidence values stay
  identity-free.
  """

  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.Tier

  @type t :: %__MODULE__{
          tier: Tier.t(),
          budget: pos_integer(),
          alternative: Study.strategy(),
          reference: Study.strategy(),
          outcome: String.t()
        }

  defstruct [:tier, :budget, :alternative, :reference, :outcome]
end
