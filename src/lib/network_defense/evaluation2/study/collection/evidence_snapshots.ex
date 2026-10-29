defmodule NetworkDefense.Evaluation2.Study.Collection.EvidenceSnapshots do
  @moduledoc false

  # Accepted evidence of one collection phase.
  #
  # `assemble/1` accepts one collection phase identifier and derives everything
  # else from application-owned records: the Pilot or Final role, the phase runs
  # in declared order, the immutable definition, and the accepted replica.
  #
  # Pilot assembly reads its single phase run. Final assembly reads the tier runs
  # in declared tier order and uses measured replica 0. The builder creates one
  # shared attack-column list per comparison and fills both sides at their declared
  # positions, so later stages need no realignment pass.
  #
  # A retried assembly returns the phase-owned snapshot. Assembly runs after the
  # mapped collection tasks succeeded, so an accepted snapshot covers completed
  # work.

  alias NetworkDefense.Evaluation2.EvidenceSnapshot
  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study.Error

  # Assemble or load the evidence snapshot of one collection phase.
  #
  # The caller passes a collection phase. The phase owns the snapshot and states
  # its Pilot or Final role.
  @spec assemble(Ecto.UUID.t()) :: {:ok, EvidenceSnapshot.t()} | {:error, Error.t()}
  def assemble(_study_phase_id), do: {:error, Placeholder.error(:assemble)}

  # Load the accepted snapshot of one collection phase.
  #
  # Gust success of the assembly task guarantees that the snapshot exists.
  @spec fetch_for_phase!(Ecto.UUID.t()) :: EvidenceSnapshot.t()
  def fetch_for_phase!(_study_phase_id),
    do: raise(NotImplementedError, function: :fetch_for_phase!)
end
