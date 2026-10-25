defmodule NetworkDefense.Evaluation.StudyPhase do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  # One row for one fixed phase of one study execution.
  #
  # A phase row links the execution, the phase, the Gust run that performs the
  # work, and either the accepted evidence snapshot or the accepted result
  # reference. The error carries a bounded envelope and never raw diagnostics.
  #
  # The database enforces one row for each execution and phase pair. Phase
  # attempts, replay lineage, and an active-phase pointer are outside the
  # prototype.

  @phases [
    :pilot_collection,
    :pilot_analysis,
    :final_collection,
    :final_analysis
  ]

  @fields [:execution_id, :phase, :gust_run_id, :snapshot_id, :result_ref, :error]

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "evaluation_study_phases" do
    field :execution_id, :binary_id
    field :phase, Ecto.Enum, values: @phases
    field :gust_run_id, :integer
    field :snapshot_id, :binary_id
    field :result_ref, :map
    field :error, :map

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{
          id: binary(),
          execution_id: binary(),
          phase: :pilot_collection | :pilot_analysis | :final_collection | :final_analysis,
          gust_run_id: integer() | nil,
          snapshot_id: binary() | nil,
          result_ref: map() | nil,
          error: map() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  def changeset(phase, attrs) do
    phase
    |> cast(attrs, @fields)
    |> validate_required([:execution_id, :phase])
    |> unique_constraint([:execution_id, :phase],
      name: :evaluation_study_phases_execution_id_phase_index
    )
    |> check_constraint(:phase,
      name: :evaluation_study_phases_phase_valid,
      message: "is not a declared study phase"
    )
  end
end
