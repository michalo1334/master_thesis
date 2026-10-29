defmodule NetworkDefense.Evaluation2.EvidenceSnapshot do
  @moduledoc false

  # Accepted evidence of one collection phase.
  #
  # A snapshot belongs to the collection `StudyPhase` that assembled it, and the
  # owning phase states the Pilot or Final role. Assembly creates the snapshot
  # once, and a retried assembly returns the same snapshot.
  #
  # Analysis reads the snapshot by identifier and rebuilds no optimization or
  # simulation history.

  alias NetworkDefense.Evaluation2.Evidence

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          study_phase_id: Ecto.UUID.t(),
          evidence: Evidence.t()
        }

  defstruct [:id, :study_phase_id, :evidence]
end
