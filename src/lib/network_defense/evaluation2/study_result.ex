defmodule NetworkDefense.Evaluation2.StudyResult do
  @moduledoc """
  Stored result of one successful execution.

  The result keeps the compact Pilot outcome, the frozen Final selection, the
  corrected Final family, and the measured timing. Reporting tools read this
  record instead of rebuilding domain history.
  """

  alias NetworkDefense.Evaluation2.CorrectedFamily
  alias NetworkDefense.Evaluation2.PilotOutcome
  alias NetworkDefense.Evaluation2.Selection
  alias NetworkDefense.Evaluation2.Timing.TimingSummary

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          execution_id: Ecto.UUID.t(),
          schema_version: 1,
          pilot_outcome: PilotOutcome.t(),
          selection: Selection.t(),
          family: CorrectedFamily.t(),
          timing: TimingSummary.t()
        }

  defstruct [
    :id,
    :execution_id,
    :schema_version,
    :pilot_outcome,
    :selection,
    :family,
    :timing
  ]
end
