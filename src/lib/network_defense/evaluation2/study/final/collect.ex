defmodule NetworkDefense.Evaluation2.Study.Final.Collect do
  @moduledoc false

  # Collection of the Final phase.
  #
  # Final collection runs one Gust run per declared tier, in the closed tier
  # order, and awaits each run before it starts the next. Every tier run measures
  # the warm-up and the five measured replicas against the frozen selection.
  #
  # Acceptance compares the measured replicas and rejects a tier whose replicas
  # disagree. Timing values and run identifiers stay outside that gate.
  #
  # The aggregate is transient. The accepted snapshot, the phase-run links, and
  # the Gust timing results remain the durable owners, so a restart rebuilds the
  # aggregate from them.

  alias NetworkDefense.Evaluation2.EvidenceSnapshot
  alias NetworkDefense.Evaluation2.FinalTierRunResult
  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Result.Timing
  alias NetworkDefense.Evaluation2.StudyExecution

  # Collect every declared Final tier of one execution.
  #
  # A failed tier fails Final collection, and no replacement replica runs.
  @spec run(StudyExecution.t()) ::
          {:ok, EvidenceSnapshot.t(), Timing.t()} | {:error, Error.t()}
  def run(_execution), do: {:error, Placeholder.error(:run)}

  # Accept completed tier runs.
  #
  # The received tier runs follow the closed tier order. The replica equality gate
  # runs before the snapshot and the timing value are created.
  @spec accept([FinalTierRunResult.t()], StudyExecution.t()) ::
          {:ok, EvidenceSnapshot.t(), Timing.t()} | {:error, Error.t()}
  def accept(_tier_results, _execution), do: {:error, Placeholder.error(:accept)}
end
