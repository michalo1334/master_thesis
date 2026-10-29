defmodule NetworkDefense.Evaluation2.StudyPhaseRun do
  @moduledoc false

  # Link between one study phase and one Gust run.
  #
  # Every Gust run has one phase-run record. Single-run phases use the `:single`
  # key, and Final collection uses one tier key per declared tier.
  #
  # Gust owns run status, task status, task results, and task errors. This record
  # keeps the application-to-Gust link only.

  alias NetworkDefense.Evaluation2.Study.Tier

  @typedoc "Run key of one phase run: the single phase run or one declared tier."
  @type run_key :: :single | {:tier, Tier.t()}

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          study_phase_id: Ecto.UUID.t(),
          key: run_key(),
          gust_run_id: pos_integer()
        }

  defstruct [:id, :study_phase_id, :key, :gust_run_id]
end
