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

  @fields [
    :study_revision_id,
    :state,
    :pilot_outcome,
    :selected_candidate_id,
    :selected_plan_count_per_side,
    :selected_attacks_per_plan,
    :pilot_override,
    :error
  ]

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
    field :selected_candidate_id, :string
    field :selected_plan_count_per_side, :integer
    field :selected_attacks_per_plan, :integer
    field :pilot_override, :boolean
    field :error, :map

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{
          id: binary(),
          study_revision_id: binary(),
          state: NetworkDefense.Evaluation.Study.Lifecycle.state(),
          pilot_outcome: map() | nil,
          selected_candidate_id: String.t() | nil,
          selected_plan_count_per_side: pos_integer() | nil,
          selected_attacks_per_plan: pos_integer() | nil,
          pilot_override: boolean() | nil,
          error: map() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  def changeset(execution, attrs) do
    execution
    |> cast(attrs, @fields)
    |> validate_required([:study_revision_id, :state])
    |> validate_length(:selected_candidate_id, min: 1, max: 128)
    |> validate_number(:selected_plan_count_per_side, greater_than: 0)
    |> validate_number(:selected_attacks_per_plan, greater_than: 0)
    |> check_constraint(:state,
      name: :evaluation_study_executions_state_valid,
      message: "is not a declared study state"
    )
    |> check_constraint(:selected_candidate_id,
      name: :evaluation_study_executions_final_selection_all_or_none,
      message: "must be stored as one complete Final selection"
    )
    |> check_constraint(:selected_candidate_id,
      name: :evaluation_study_executions_selected_candidate_id_valid,
      message: "must be between 1 and 128 characters"
    )
    |> check_constraint(:selected_plan_count_per_side,
      name: :evaluation_study_executions_selected_plan_count_positive,
      message: "must be greater than 0"
    )
    |> check_constraint(:selected_attacks_per_plan,
      name: :evaluation_study_executions_selected_attacks_per_plan_positive,
      message: "must be greater than 0"
    )
  end
end
