defmodule NetworkDefense.Evaluation2.CandidateSummary do
  @moduledoc false

  # The terminal Pilot output owns comparison details for selection and reports.
  # Aggregate values are derived, so they cannot diverge from those details.
  alias NetworkDefense.Evaluation2.CandidateSummary.Comparison
  alias NetworkDefense.Evaluation2.Study

  defmodule Comparison do
    @moduledoc false

    @type t :: %__MODULE__{
            comparison_position: non_neg_integer(),
            guarded_half_width: float(),
            informative: boolean(),
            passes: boolean()
          }

    defstruct [:comparison_position, :guarded_half_width, :informative, :passes]
  end

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
