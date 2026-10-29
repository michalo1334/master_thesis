defmodule NetworkDefense.Evaluation2.Study.PilotResult.Candidate do
  @moduledoc """
  One declared Pilot candidate of a Pilot report.

  The candidate names its declared sample counts and holds one assessment per
  declared comparison. The comparison order follows the immutable definition.

  The aggregate values are derived from the comparison list: the worst guarded
  half-width, the informativeness, the non-informative comparisons, and the pass
  decision.
  """

  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.PilotResult.Comparison

  @type t :: %__MODULE__{
          id: Study.candidate_id(),
          plan_count_per_side: pos_integer(),
          attacks_per_plan: pos_integer(),
          predicted_runtime_ms: number(),
          comparisons: [Comparison.t()]
        }

  defstruct [
    :id,
    :plan_count_per_side,
    :attacks_per_plan,
    :predicted_runtime_ms,
    :comparisons
  ]

  @doc "Return the largest guarded half-width of the candidate, or `nil` without comparisons."
  @spec worst_guarded_half_width(t()) :: float() | nil
  def worst_guarded_half_width(%__MODULE__{comparisons: []}), do: nil

  def worst_guarded_half_width(%__MODULE__{comparisons: comparisons}) do
    comparisons
    |> Enum.map(& &1.guarded_half_width)
    |> Enum.max()
  end

  @doc "Return `true` when every declared comparison is informative."
  @spec informative?(t()) :: boolean()
  def informative?(%__MODULE__{comparisons: comparisons}) do
    Enum.all?(comparisons, & &1.informative)
  end

  @doc "Return the comparisons whose outer subsamples were not all informative."
  @spec non_informative_comparisons(t()) :: [Comparison.t()]
  def non_informative_comparisons(%__MODULE__{comparisons: comparisons}) do
    Enum.reject(comparisons, & &1.informative)
  end

  @doc "Return `true` when every declared comparison passed."
  @spec passes?(t()) :: boolean()
  def passes?(%__MODULE__{comparisons: comparisons}) do
    Enum.all?(comparisons, & &1.passes)
  end
end
