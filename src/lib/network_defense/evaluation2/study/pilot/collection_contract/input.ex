defmodule NetworkDefense.Evaluation2.Study.Pilot.CollectionContract.Input do
  @moduledoc false

  # Root input of one Pilot collection Gust run.
  #
  # The phase run identifies the planned work of that run.

  @type t :: %__MODULE__{phase_run_id: Ecto.UUID.t()}

  defstruct [:phase_run_id]
end
