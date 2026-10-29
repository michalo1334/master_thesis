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

  alias NetworkDefense.Evaluation2.Study.{Error, Lifecycle, PilotOutcome, Selection}

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          study_revision_id: Ecto.UUID.t(),
          state: Lifecycle.state(),
          pilot_outcome: PilotOutcome.t() | nil,
          selection: Selection.t() | nil,
          error: Error.t() | nil
        }

  defstruct [
    :id,
    :study_revision_id,
    :state,
    :pilot_outcome,
    :selection,
    :error
  ]
end
