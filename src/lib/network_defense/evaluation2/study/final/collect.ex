defmodule NetworkDefense.Evaluation2.Study.Final.Collect do
  @moduledoc """
  Collection of the Final phase.

  Final collection runs one Gust run per declared tier, in the closed tier order,
  and awaits each run before it starts the next. Every tier run measures the
  declared replicas against the frozen selection.

  Acceptance compares the measured replicas of a tier and rejects a tier whose
  replicas disagree. Timing values and run identifiers are outside that gate.
  """

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError

  alias NetworkDefense.Evaluation2.{
    FinalCollectionOutput,
    FinalTierRunResult,
    NotImplementedError
  }

  alias NetworkDefense.Evaluation2.StudyExecution

  @doc """
  Collect every declared Final tier of one execution.

  The result names the accepted snapshot, the ordered tier runs, and the measured
  timing. A failed tier fails Final collection; no replacement replica runs.
  """
  @spec run(StudyExecution.t()) ::
          {:ok, FinalCollectionOutput.t()} | {:error, StudyError.t()}
  def run(_execution), do: raise(NotImplementedError, function: :run)

  @doc """
  Accept completed tier runs.

  The received tier runs follow the closed tier order. The replica equality gate
  runs before the snapshot and the timing summary are created.
  """
  @spec accept([FinalTierRunResult.t()]) ::
          {:ok, FinalCollectionOutput.t()} | {:error, StudyError.t()}
  def accept(_tier_results), do: raise(NotImplementedError, function: :accept)
end
