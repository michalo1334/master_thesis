defmodule NetworkDefense.Evaluation2.FinalCollectionOutput do
  @moduledoc """
  Aggregate output of Final collection.

  Final collection is an application stage, so this value is not a Gust DAG
  output. It exists after every declared tier run passed the replica equality gate,
  and it names the accepted snapshot, the tier runs in closed tier order, and the
  measured timing.
  """

  alias NetworkDefense.Evaluation2.Tier
  alias NetworkDefense.Evaluation2.Timing.TimingSummary

  @typedoc "Identity of one accepted Final tier run."
  @type tier_run :: %{tier: Tier.t(), gust_run_id: pos_integer()}

  @type t :: %__MODULE__{
          snapshot_id: Ecto.UUID.t(),
          tier_runs: [tier_run()],
          timing: TimingSummary.t()
        }

  defstruct [:snapshot_id, :tier_runs, :timing]
end
