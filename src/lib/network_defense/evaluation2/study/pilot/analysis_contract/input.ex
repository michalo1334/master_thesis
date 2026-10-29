defmodule NetworkDefense.Evaluation2.Study.Pilot.AnalysisContract.Input do
  @moduledoc false

  # Root input of one Pilot analysis Gust run.
  #
  # The phase run owns the candidate and comparison jobs, and the snapshot holds
  # the accepted Pilot matrices.

  @type t :: %__MODULE__{
          phase_run_id: Ecto.UUID.t(),
          snapshot_id: Ecto.UUID.t()
        }

  defstruct [:phase_run_id, :snapshot_id]
end
