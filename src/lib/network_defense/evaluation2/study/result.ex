defmodule NetworkDefense.Evaluation2.Study.Result do
  @moduledoc """
  Result of one successful study.

  The value joins the execution-owned Pilot history with the Final-owned
  corrected family and measured timing. All fields are present because the value
  exists only after success.

  Complete Pilot candidate detail belongs to
  `NetworkDefense.Evaluation2.Study.PilotResult`.
  """

  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.{PilotOutcome, Revision, Selection}
  alias NetworkDefense.Evaluation2.Study.Result.{Family, Timing}

  @type t :: %__MODULE__{
          execution_id: Study.execution_id(),
          revision: Revision.t(),
          pilot_outcome: PilotOutcome.t(),
          selection: Selection.t(),
          family: Family.t(),
          timing: Timing.t()
        }

  defstruct [:execution_id, :revision, :pilot_outcome, :selection, :family, :timing]
end
