defmodule NetworkDefense.Evaluation2.Study.Final.TierContract.Input do
  @moduledoc false

  # Root input of one Final tier collection Gust run.
  #
  # The phase run identifies the tier plan that every replica of the tier reuses.

  @type t :: %__MODULE__{phase_run_id: Ecto.UUID.t()}

  defstruct [:phase_run_id]
end
