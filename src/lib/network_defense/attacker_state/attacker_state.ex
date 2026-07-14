defmodule NetworkDefense.AttackerState.AttackerState do
  @moduledoc """
  Tracks the resources currently controlled by an attacker during one simulation.
  """

  defstruct [
    :footholds,
    :attack_frontier
  ]

  def new(attack_frontier) do
    %__MODULE__{
      footholds: [],
      attack_frontier: attack_frontier
    }
  end

  def foothold_nodes(state), do: state.footholds
end
