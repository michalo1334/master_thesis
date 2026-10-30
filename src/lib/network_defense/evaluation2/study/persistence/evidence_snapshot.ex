defmodule NetworkDefense.Evaluation2.Study.Persistence.EvidenceSnapshot do
  @moduledoc false

  # Assembled evidence of one collection phase.
  #
  # A snapshot belongs to the collection `StudyPhase` that assembled it, and the
  # owning phase states the Pilot or Final role. Assembly creates it once, and a
  # retried assembly returns the same snapshot. The snapshot records the prepared
  # evidence; the lifecycle decides separately whether the phase is accepted.
  #
  # The stored `evidence` JSONB value decodes back into `Study.Evidence` at the
  # persistence boundary.

  use Ecto.Schema

  alias NetworkDefense.Evaluation2.Study.Evidence

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          study_phase_id: Ecto.UUID.t(),
          evidence: Evidence.t(),
          inserted_at: DateTime.t()
        }

  schema "evaluation2_evidence_snapshots" do
    field :study_phase_id, :binary_id
    field :evidence, :map

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
