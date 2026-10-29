defmodule NetworkDefense.Evaluation2.Study.Status do
  @moduledoc """
  Lifecycle view of one study execution.

  The struct is one value with a state-refined type. Each state fixes which
  accepted values exist: Pilot outcome, frozen selection, and terminal error.
  Only the failed and cancelled variants keep optional accepted context.

  Complete Pilot candidate detail belongs to `NetworkDefense.Evaluation2.Study.PilotResult`.
  """

  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.{Error, PilotOutcome, Revision, Selection}

  @type t ::
          pilot_running()
          | awaiting_final()
          | final_running()
          | succeeded()
          | failed()
          | cancelled()

  @typedoc "The execution is collecting or analyzing Pilot evidence."
  @type pilot_running :: %__MODULE__{
          execution_id: Study.execution_id(),
          revision: Revision.t(),
          state: :collecting_pilot | :analyzing_pilot,
          pilot_outcome: nil,
          selection: nil,
          error: nil
        }

  @typedoc "The Pilot outcome is accepted and Final collection waits for approval."
  @type awaiting_final :: %__MODULE__{
          execution_id: Study.execution_id(),
          revision: Revision.t(),
          state: :awaiting_final,
          pilot_outcome: PilotOutcome.t(),
          selection: nil,
          error: nil
        }

  @typedoc "The execution is collecting or analyzing Final evidence."
  @type final_running :: %__MODULE__{
          execution_id: Study.execution_id(),
          revision: Revision.t(),
          state: :collecting_final | :analyzing_final,
          pilot_outcome: PilotOutcome.t(),
          selection: Selection.t(),
          error: nil
        }

  @typedoc "The execution produced a stored result."
  @type succeeded :: %__MODULE__{
          execution_id: Study.execution_id(),
          revision: Revision.t(),
          state: :succeeded,
          pilot_outcome: PilotOutcome.t(),
          selection: Selection.t(),
          error: nil
        }

  @typedoc "The execution failed. Accepted context stays visible when it exists."
  @type failed :: %__MODULE__{
          execution_id: Study.execution_id(),
          revision: Revision.t(),
          state: :failed,
          pilot_outcome: PilotOutcome.t() | nil,
          selection: Selection.t() | nil,
          error: Error.t()
        }

  @typedoc "The execution was cancelled. Accepted context stays visible when it exists."
  @type cancelled :: %__MODULE__{
          execution_id: Study.execution_id(),
          revision: Revision.t(),
          state: :cancelled,
          pilot_outcome: PilotOutcome.t() | nil,
          selection: Selection.t() | nil,
          error: nil
        }

  defstruct [:execution_id, :revision, :state, :pilot_outcome, :selection, :error]
end
