defmodule NetworkDefense.Simulation.IterationStep do
  @moduledoc """
  Represents single iteration step of a simulation.

  Contains information related to single interation step.
  """
  alias NetworkDefense.Actions.Action
  alias NetworkDefense.AttackerState.AttackerState

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          attempted_action: Action | nil,
          success?: boolean(),
          attacker_state: AttackerState
        }

  defstruct [
    :index,
    :attempted_action,
    :success?,
    :attacker_state,
    :seed
  ]

  def new(opts \\ []) do
    struct!(__MODULE__, opts)
  end
end
