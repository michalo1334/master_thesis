defmodule NetworkDefense.Evaluation2.Study.Persistence.Phase do
  @moduledoc false

  # One declared phase of a study execution.
  #
  # The phase groups the Gust runs that perform the declared phase work and gives
  # acceptance one transaction target. Gust run identity belongs to
  # `StudyPhaseRun`, evidence belongs to `EvidenceSnapshot`, and lifecycle data
  # belongs to `StudyExecution`.
  #
  # The collection phase kind states the Pilot or Final role of its evidence.

  use Ecto.Schema

  @phase_kinds [:pilot_collection, :pilot_analysis, :final_collection, :final_analysis]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @typedoc "One declared phase of the study pipeline."
  @type phase_kind :: :pilot_collection | :pilot_analysis | :final_collection | :final_analysis

  @typedoc "Pilot or Final role of one collection phase."
  @type evidence_role :: :pilot | :final

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          study_execution_id: Ecto.UUID.t(),
          phase: phase_kind(),
          inserted_at: DateTime.t()
        }

  schema "evaluation2_study_phases" do
    field :study_execution_id, :binary_id
    field :phase, Ecto.Enum, values: @phase_kinds

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @spec evidence_role(phase_kind()) :: evidence_role() | nil
  def evidence_role(:pilot_collection), do: :pilot
  def evidence_role(:final_collection), do: :final
  def evidence_role(_analysis_phase), do: nil
end
