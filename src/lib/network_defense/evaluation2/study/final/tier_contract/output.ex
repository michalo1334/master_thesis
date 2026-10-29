defmodule NetworkDefense.Evaluation2.Study.Final.TierContract.Output do
  @moduledoc false

  # Terminal output of one Final tier collection Gust run.
  #
  # The coordinator owns the measured timing and the phase run owns its results,
  # so Gust success carries no payload.

  @type t :: %__MODULE__{}

  defstruct []
end
