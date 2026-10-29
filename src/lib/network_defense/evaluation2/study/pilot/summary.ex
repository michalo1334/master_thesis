defmodule NetworkDefense.Evaluation2.Study.Pilot.Summary do
  @moduledoc false

  # Complete terminal summary of one Pilot candidate.
  #
  # The terminal Pilot output owns the comparison detail that selection and the
  # supported Pilot report both need. Aggregate values are derived from that
  # detail, so they cannot diverge from it.
  #
  # The candidate identifier names a sample-size choice of the Pilot grid and is
  # not a network-size tier.

  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.Pilot.Summary.Comparison

  @type t :: %__MODULE__{
          candidate_position: non_neg_integer(),
          candidate_id: Study.candidate_id(),
          plan_count_per_side: pos_integer(),
          attacks_per_plan: pos_integer(),
          predicted_runtime_ms: number(),
          comparisons: [Comparison.t()]
        }

  defstruct [
    :candidate_position,
    :candidate_id,
    :plan_count_per_side,
    :attacks_per_plan,
    :predicted_runtime_ms,
    :comparisons
  ]

  @spec worst_guarded_half_width(t()) :: float() | nil
  def worst_guarded_half_width(%__MODULE__{comparisons: comparisons}) do
    comparisons |> Enum.map(& &1.guarded_half_width) |> Enum.max(fn -> nil end)
  end

  @spec informative?(t()) :: boolean()
  def informative?(%__MODULE__{comparisons: comparisons}),
    do: Enum.all?(comparisons, & &1.informative)

  @spec non_informative_comparisons(t()) :: [non_neg_integer()]
  def non_informative_comparisons(%__MODULE__{comparisons: comparisons}) do
    comparisons |> Enum.reject(& &1.informative) |> Enum.map(& &1.comparison_position)
  end

  @spec passes?(t()) :: boolean()
  def passes?(%__MODULE__{comparisons: comparisons}), do: Enum.all?(comparisons, & &1.passes)
end
