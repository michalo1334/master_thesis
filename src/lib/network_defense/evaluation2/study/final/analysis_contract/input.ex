defmodule NetworkDefense.Evaluation2.Study.Final.AnalysisContract.Input do
  @moduledoc false

  # Root input of one Final analysis Gust run.
  #
  # The phase run owns the declared comparison jobs, and the snapshot holds the
  # accepted Final matrices.

  @type t :: %__MODULE__{
          phase_run_id: Ecto.UUID.t(),
          snapshot_id: Ecto.UUID.t()
        }

  defstruct [:phase_run_id, :snapshot_id]
end
