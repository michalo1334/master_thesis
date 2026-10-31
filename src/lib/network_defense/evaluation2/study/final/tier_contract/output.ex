defmodule NetworkDefense.Evaluation2.Study.Final.TierContract.Output do
  @moduledoc false

  # Terminal receipt of one Final tier collection Gust run.
  #
  # The receipt binds the tier to its clock session and keeps the measured
  # durations of the five replicas. Raw clock readings stay in the clock
  # process, so the stored receipt rebuilds the summary after the clock is gone.

  alias NetworkDefense.Evaluation2.Study.Result.Timing
  alias NetworkDefense.Evaluation2.Study.Tier, as: StudyTier

  @type t :: %__MODULE__{
          phase_run_id: Ecto.UUID.t(),
          tier: StudyTier.t(),
          clock_session: String.t(),
          timing: Timing.Tier.t()
        }

  defstruct [:phase_run_id, :tier, :clock_session, :timing]
end
