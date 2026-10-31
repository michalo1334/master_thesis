defmodule NetworkDefense.Evaluation2.Study.Workflow.FinalTierCollection.Actions.Prepared do
  @moduledoc false

  # Stored result of the tier preparation task.
  #
  # The clock session is the handle of one tier timing session, so every later
  # task of the run recovers this value instead of opening a second session. The
  # tier and the phase run stay next to the session, because the terminal task
  # encodes them into its output.

  alias NetworkDefense.Evaluation2.Study.Tier

  @type t :: %__MODULE__{
          plan_id: Ecto.UUID.t(),
          clock_session: binary(),
          phase_run_id: Ecto.UUID.t(),
          tier: Tier.t()
        }

  defstruct [:plan_id, :clock_session, :phase_run_id, :tier]
end
