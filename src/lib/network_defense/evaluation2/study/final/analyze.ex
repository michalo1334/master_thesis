defmodule NetworkDefense.Evaluation2.Study.Final.Analyze do
  @moduledoc """
  Comparison analysis of the Final phase.

  Preparation turns the declared family into one comparison job per declared
  member. Each job compares the accepted Final matrices of its comparison. The
  correction step applies the declared family correction, so Pilot and Final share
  one declared comparison order.
  """

  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonStatistics
  alias NetworkDefense.Evaluation.Study.Contracts.Definition, as: StudyDefinition
  alias NetworkDefense.Evaluation2.CorrectedFamily
  alias NetworkDefense.Evaluation2.{EvidenceSnapshot, FinalComparison, NotImplementedError}
  alias NetworkDefense.Evaluation2.Study.Definition

  @doc """
  Prepare the Final analysis jobs of one definition.

  Job positions follow the declared family order.
  """
  @spec prepare(EvidenceSnapshot.t(), Definition.t()) :: [FinalComparison.t()]
  def prepare(_snapshot, _definition), do: raise(NotImplementedError, function: :prepare)

  @doc """
  Compare one declared family member.

  The comparison reads the aligned matrices of the accepted Final snapshot.
  """
  @spec run(Ecto.UUID.t(), FinalComparison.t()) :: ComparisonStatistics.t()
  def run(_phase_id, _final_comparison), do: raise(NotImplementedError, function: :run)

  @doc """
  Correct the declared comparison family.

  The corrected family keeps the per-comparison statistics and adds one adjustment
  per declared comparison.
  """
  @spec correct([ComparisonStatistics.t()], StudyDefinition.Family.t()) ::
          CorrectedFamily.t()
  def correct(_statistics, _family), do: raise(NotImplementedError, function: :correct)
end
