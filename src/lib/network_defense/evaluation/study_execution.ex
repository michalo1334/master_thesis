defmodule NetworkDefense.Evaluation.StudyExecution do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  # One mutable study execution.
  #
  # The record holds the revision it executes, the lifecycle state, and an
  # optional terminal error. The lifecycle module owns the state vocabulary and
  # the accepted transitions; the database keeps the matching closed set. The
  # error carries a bounded envelope and never raw diagnostics or evidence.
  #
  # Accepted phase references live in `StudyPhase` rows, one row for each fixed
  # phase. A selected candidate, the Pilot outcome, and the override flag join
  # this record only when their behavior becomes active.

  @fields [:study_revision_id, :state, :pilot_outcome, :error]

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "evaluation_study_executions" do
    field :study_revision_id, :binary_id

    field :state, Ecto.Enum,
      values: [
        :collecting_pilot,
        :analyzing_pilot,
        :awaiting_final,
        :collecting_final,
        :analyzing_final,
        :succeeded,
        :failed,
        :cancelled
      ]

    field :pilot_outcome, :map
    field :error, :map

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{
          id: binary(),
          study_revision_id: binary(),
          state: NetworkDefense.Evaluation.Study.Lifecycle.state(),
          pilot_outcome: map() | nil,
          error: map() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  def changeset(execution, attrs) do
    execution
    |> cast(attrs, @fields)
    |> validate_required([:study_revision_id, :state])
    |> check_constraint(:state,
      name: :evaluation_study_executions_state_valid,
      message: "is not a declared study state"
    )
  end
end
