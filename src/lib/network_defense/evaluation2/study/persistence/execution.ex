defmodule NetworkDefense.Evaluation2.Study.Persistence.Execution do
  @moduledoc false

  # Lifecycle record of one study execution.
  #
  # The record keeps the revision under execution, the current lifecycle state,
  # the compact Pilot outcome, the frozen Final selection, and one bounded
  # terminal error.
  #
  # Accepted Gust runs, snapshots, and results live in their own records, so this
  # record stays small. The Pilot outcome has this single owner, and the selection
  # is one nested value instead of four optional columns.
  #
  # The state column stores the closed lifecycle vocabulary. `Study.Persistence`
  # replaces the JSONB values with their typed shapes before the record leaves the
  # boundary.

  use Ecto.Schema

  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Lifecycle
  alias NetworkDefense.Evaluation2.Study.PilotOutcome
  alias NetworkDefense.Evaluation2.Study.Selection

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          study_revision_id: Ecto.UUID.t(),
          state: Lifecycle.state(),
          pilot_outcome: PilotOutcome.t() | nil,
          selection: Selection.t() | nil,
          error: Error.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "evaluation2_study_executions" do
    field :study_revision_id, :binary_id
    field :state, Ecto.Enum, values: Lifecycle.states()
    field :pilot_outcome, :map
    field :selection, :map
    field :error, :map

    timestamps(type: :utc_datetime_usec)
  end
end
