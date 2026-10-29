defmodule NetworkDefense.Evaluation2.Study.Pilot.CollectionContract.Output do
  @moduledoc false

  # Terminal output of one Pilot collection Gust run.
  #
  # The collection phase owns the assembled snapshot, so Gust success carries no
  # payload.

  @type t :: %__MODULE__{}

  defstruct []
end
