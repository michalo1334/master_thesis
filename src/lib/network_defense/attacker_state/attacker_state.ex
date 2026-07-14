defmodule NetworkDefense.AttackerState.AttackerState do
  @moduledoc """
  Tracks the resources currently controlled by an attacker during one simulation.
  """

  @type t :: %__MODULE__{}

  defstruct footholds: MapSet.new(), attempted_actions: MapSet.new()

  def new(initial_foothold_id), do: %__MODULE__{footholds: MapSet.new([initial_foothold_id])}

  def foothold_nodes(state), do: MapSet.to_list(state.footholds)

  def add_foothold(state, host_id), do: %{state | footholds: MapSet.put(state.footholds, host_id)}

  def attempted?(state, action_key), do: MapSet.member?(state.attempted_actions, action_key)

  def mark_attempted(state, action_key) do
    %{state | attempted_actions: MapSet.put(state.attempted_actions, action_key)}
  end
end
