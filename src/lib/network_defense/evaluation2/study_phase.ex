defmodule NetworkDefense.Evaluation2.StudyPhase do
  @moduledoc """
  Accepted Gust run and output of one declared study phase.

  One record exists for each execution and phase pair. It links the execution to
  the Gust run that performed the phase work, to the accepted evidence snapshot
  of a collection phase, and to the decoded terminal output of an analysis
  phase. Lifecycle acceptance owns the state check; this record owns identity.
  """

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError

  @type phase :: :pilot_collection | :pilot_analysis | :final_collection | :final_analysis

  @typedoc "Decoded terminal contract output of an analysis phase."
  @type accepted_output :: struct() | nil

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          execution_id: Ecto.UUID.t(),
          phase: phase(),
          gust_run_id: pos_integer() | nil,
          snapshot_id: Ecto.UUID.t() | nil,
          output: accepted_output(),
          error: StudyError.t() | nil
        }

  defstruct [:id, :execution_id, :phase, :gust_run_id, :snapshot_id, :output, :error]
end
