defmodule NetworkDefense.Evaluation2.Study.Definition.FinalCollection do
  @moduledoc false

  alias NetworkDefense.Evaluation2.Study.Definition.TierRoot

  @type t :: %__MODULE__{selection_seeds: [non_neg_integer()], roots: [TierRoot.t()]}
  defstruct [:selection_seeds, :roots]
end
