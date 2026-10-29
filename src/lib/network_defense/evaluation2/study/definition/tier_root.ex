defmodule NetworkDefense.Evaluation2.Study.Definition.TierRoot do
  @moduledoc false

  # Roots associate declared network tiers with collection seed values.
  @type t :: %__MODULE__{tier: String.t(), value: non_neg_integer()}
  defstruct [:tier, :value]
end
