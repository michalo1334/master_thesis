defmodule NetworkDefense.Evaluation2.Study.Final.TierRun do
  @moduledoc false

  # Combined result of one Final tier run.
  #
  # The runner joins the tier coordinate of the collection loop with the Gust run
  # identity and the timing that the coordinator measured for that run.
  # The value is transient.
  #
  # The clock session binds the measured values to one clock owner. Warm-up
  # produces no tier run, because it contributes no measured values.
  alias NetworkDefense.Evaluation2.Study.Final.TierContract.Output
  alias NetworkDefense.Evaluation2.Study.Result.Timing
  alias NetworkDefense.Evaluation2.Study.Tier

  @type t :: %__MODULE__{
          tier: Tier.t(),
          gust_run_id: pos_integer(),
          timing: Timing.Tier.t(),
          phase_run_id: Ecto.UUID.t() | nil,
          clock_session: String.t() | nil
        }

  defstruct [:tier, :gust_run_id, :timing, :phase_run_id, :clock_session]

  @doc """
  Build the transient tier result from a decoded terminal Gust result.

  The stored receipt keeps the phase run and the clock session, so a summary
  rebuilt after caller loss still names the work it measured.
  """
  @spec from_output(pos_integer(), Output.t()) :: t()
  def from_output(gust_run_id, %Output{} = output) do
    %__MODULE__{
      tier: output.tier,
      gust_run_id: gust_run_id,
      timing: output.timing,
      phase_run_id: output.phase_run_id,
      clock_session: output.clock_session
    }
  end
end
