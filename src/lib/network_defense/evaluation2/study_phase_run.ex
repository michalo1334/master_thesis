defmodule NetworkDefense.Evaluation2.StudyPhaseRun do
  @moduledoc """
  One Final tier Gust run.

  The Final collection phase owns one record per study tier and keeps the Gust run
  that collected that tier. Sequential tier order comes from the closed
  `NetworkDefense.Evaluation2.Tier` order, so the record stores no tier position.
  """

  alias NetworkDefense.Evaluation2.Tier

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          study_phase_id: Ecto.UUID.t(),
          tier: Tier.t(),
          gust_run_id: pos_integer() | nil
        }

  defstruct [:id, :study_phase_id, :tier, :gust_run_id]
end
