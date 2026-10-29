defmodule NetworkDefense.Evaluation2.StudyExecution do
  @moduledoc """
  Lifecycle record of one study execution.

  The record keeps the revision under execution, the current lifecycle state,
  the compact Pilot outcome, the frozen Final selection, and one bounded
  terminal error. Accepted Gust runs and phase outputs live in `StudyPhase` and
  `StudyPhaseRun` rows, so this record stays small.
  """

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation2.PilotOutcome
  alias NetworkDefense.Evaluation2.Study.Lifecycle

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          study_revision_id: Ecto.UUID.t(),
          state: Lifecycle.state(),
          pilot_outcome: PilotOutcome.t() | nil,
          selected_candidate_id: PilotOutcome.candidate_id() | nil,
          selected_plan_count_per_side: pos_integer() | nil,
          selected_attacks_per_plan: pos_integer() | nil,
          pilot_override: boolean() | nil,
          error: StudyError.t() | nil
        }

  defstruct [
    :id,
    :study_revision_id,
    :state,
    :pilot_outcome,
    :selected_candidate_id,
    :selected_plan_count_per_side,
    :selected_attacks_per_plan,
    :pilot_override,
    :error
  ]
end
