defmodule NetworkDefense.Evaluation2.Study.Evidence do
  @moduledoc false

  # Ordered comparison observations of one collection phase.
  #
  # Evidence holds one entry per declared family member, in declared order. Both
  # sides of one comparison share one attack-column list of
  # `NetworkDefense.Evaluation2.Study.Seed` values, and each side is one
  # `NetworkDefense.Evaluation2.Study.Matrix`.
  #
  # Family identity and comparison identity stay in the immutable definition.
  # Analysis restores readable pairs by declared position.

  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Study.Evidence.Comparison

  @type t :: %__MODULE__{comparisons: [Comparison.t()]}

  defstruct [:comparisons]

  @spec fetch_comparison!(t(), non_neg_integer()) :: Comparison.t()
  def fetch_comparison!(_evidence, _comparison_position),
    do: raise(NotImplementedError, function: :fetch_comparison!)

  @spec comparison_count(t()) :: non_neg_integer()
  def comparison_count(_evidence), do: raise(NotImplementedError, function: :comparison_count)

  @spec plan_counts(t()) :: [non_neg_integer()]
  def plan_counts(_evidence), do: raise(NotImplementedError, function: :plan_counts)

  @spec attack_count(t(), non_neg_integer()) :: non_neg_integer()
  def attack_count(_evidence, _comparison_position),
    do: raise(NotImplementedError, function: :attack_count)
end
