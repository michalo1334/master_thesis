defmodule NetworkDefense.Evaluation2.Study.Pilot.Decide do
  @moduledoc """
  Candidate decision of the Pilot phase.

  Summaries aggregate the assessments of one candidate over the declared family.
  Selection returns the passing candidate with the smallest predicted Final
  runtime, or an `:insufficient` outcome when no candidate passes every declared
  comparison.

  Tie-break order: predicted runtime, then the larger plan count, then the smaller
  attack count, then the declared candidate position.
  """

  alias NetworkDefense.Evaluation.Study.Contracts.Definition, as: StudyDefinition
  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.Evidence.Contracts.RuntimeEvidence
  alias NetworkDefense.Evaluation2.{CandidateAssessment, CandidateSummary}
  alias NetworkDefense.Evaluation2.Contracts.PilotAnalysisContract
  alias NetworkDefense.Evaluation2.NotImplementedError

  @typedoc "Ordered ranking key of one candidate summary."
  @type selection_key :: {number(), integer(), integer(), non_neg_integer()}

  @doc """
  Aggregate the assessments of every declared candidate.

  Runtime prediction follows the methodology rule: tier count, largest strategy
  group of one tier, plan count, and the declared attack count over the measured
  plan-selection and attack-trial medians.
  """
  @spec summarize(
          [CandidateAssessment.t()],
          StudyDefinition.Pilot.t(),
          StudyDefinition.Family.t(),
          RuntimeEvidence.t()
        ) :: [CandidateSummary.t()]
  def summarize(_assessments, _pilot, _family, _runtime_evidence),
    do: raise(NotImplementedError, function: :summarize)

  @doc """
  Select the Pilot outcome from the candidate summaries.

  A non-informative comparison makes its candidate non-passing. No passing
  candidate yields the `:insufficient` outcome.
  """
  @spec select([CandidateSummary.t()], selection_rule :: String.t()) ::
          PilotAnalysisContract.Output.t()
  def select(_summaries, _selection_rule), do: raise(NotImplementedError, function: :select)

  @doc "Return the ranking key of one candidate summary."
  @spec selection_key(CandidateSummary.t()) :: selection_key()
  def selection_key(_summary), do: raise(NotImplementedError, function: :selection_key)
end
