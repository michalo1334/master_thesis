defmodule NetworkDefense.Evaluation2.PilotJob do
  @moduledoc """
  One mapped Pilot analysis job.

  A job identifies one declared candidate and one declared comparison by position.
  The derived stream seed makes the historical Pilot stream reproducible, so the
  job carries no study, family, or snapshot identity.
  """

  alias NetworkDefense.Evaluation2.Seed

  @type t :: %__MODULE__{
          candidate_position: non_neg_integer(),
          comparison_position: non_neg_integer(),
          stream_seed: Seed.t()
        }

  defstruct [:candidate_position, :comparison_position, :stream_seed]
end
