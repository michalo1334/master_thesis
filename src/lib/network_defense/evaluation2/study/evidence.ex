defmodule NetworkDefense.Evaluation2.Study.Evidence do
  @moduledoc false

  use Spectral

  # Ordered comparison observations of one collection phase.
  #
  # Evidence holds one entry per declared family member, in declared order. Both
  # sides of one comparison share one attack-column list of
  # `NetworkDefense.Evaluation2.Study.Seed` values, and each side is one
  # `NetworkDefense.Evaluation2.Study.Matrix`.
  #
  # Family identity and comparison identity stay in the immutable definition.
  # Analysis restores readable pairs by declared position.

  alias NetworkDefense.Evaluation2.Study.Evidence.Comparison

  @type t :: %__MODULE__{comparisons: [Comparison.t()]}

  defstruct [:comparisons]
end
