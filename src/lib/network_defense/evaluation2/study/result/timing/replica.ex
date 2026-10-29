defmodule NetworkDefense.Evaluation2.Study.Result.Timing.Replica do
  @moduledoc """
  Measured boundaries of one Final replica.

  The three values belong to the same replica, so their correlation survives
  storage.
  """

  use Spectral

  @type t :: %__MODULE__{
          plan_selection_us: non_neg_integer(),
          simulation_us: non_neg_integer(),
          total_us: non_neg_integer()
        }

  defstruct [:plan_selection_us, :simulation_us, :total_us]
end
