defmodule NetworkDefense.Evaluation2.Study.ExecutionSummary do
  @moduledoc """
  Browse entry of one study execution.

  The value holds the accepted lifecycle state, the compact Pilot outcome, the
  frozen Final selection and the stored start and update times. It holds no
  Pilot report, no Final result, no timing triplet and no collection matrix, so
  execution history stays independent of stored scientific payloads.

  The compact Pilot outcome and the selection are the accepted values of the
  execution row; complete candidate detail belongs to
  `NetworkDefense.Evaluation2.Study.PilotResult`.
  """

  use Spectral

  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.Lifecycle
  alias NetworkDefense.Evaluation2.Study.PilotOutcome
  alias NetworkDefense.Evaluation2.Study.Revision
  alias NetworkDefense.Evaluation2.Study.Selection

  @type t :: %__MODULE__{
          execution_id: Study.execution_id(),
          revision: Revision.t(),
          state: Lifecycle.state(),
          pilot_outcome: PilotOutcome.t() | nil,
          selection: Selection.t() | nil,
          started_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :execution_id,
    :revision,
    :state,
    :pilot_outcome,
    :selection,
    :started_at,
    :updated_at
  ]
end
