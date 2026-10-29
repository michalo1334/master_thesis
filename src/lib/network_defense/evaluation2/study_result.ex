defmodule NetworkDefense.Evaluation2.StudyResult do
  @moduledoc false

  # Stored result of one successful execution.
  #
  # The record keeps the Final-owned corrected family and the raw measured
  # timing. Pilot outcome, selection, and revision stay on the successful
  # execution, so the supported result view joins both records.
  #
  # Reporting reads this record instead of rebuilding domain history.

  alias NetworkDefense.Evaluation2.CorrectedFamily
  alias NetworkDefense.Evaluation2.Study.Result.Timing

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          study_execution_id: Ecto.UUID.t(),
          family: CorrectedFamily.t(),
          timing: Timing.t()
        }

  defstruct [:id, :study_execution_id, :family, :timing]
end
