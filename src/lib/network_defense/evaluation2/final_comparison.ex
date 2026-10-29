defmodule NetworkDefense.Evaluation2.FinalComparison do
  @moduledoc """
  One mapped Final analysis job.

  A job identifies one declared comparison by position and carries the derived
  comparison stream seed. Family identity and analysis settings stay in the stored
  definition, so the job repeats no metadata.
  """

  alias NetworkDefense.Evaluation2.Seed

  @type t :: %__MODULE__{
          comparison_position: non_neg_integer(),
          stream_seed: Seed.t()
        }

  defstruct [:comparison_position, :stream_seed]
end
