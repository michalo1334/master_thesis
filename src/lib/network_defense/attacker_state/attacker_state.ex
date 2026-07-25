defmodule NetworkDefense.AttackerState.AttackerState do
  @moduledoc """
  Tracks the resources currently controlled by an attacker during one simulation.
  """

  @type t :: %__MODULE__{}

  defstruct footholds: MapSet.new(),
            attempted_actions: MapSet.new(),
            privileges: %{},
            credentials: MapSet.new()

  @privilege_order %{none: 0, user: 1, administrator: 2}

  def new(initial_foothold_id, privilege \\ :user) do
    %__MODULE__{
      footholds: MapSet.new([initial_foothold_id]),
      privileges: %{initial_foothold_id => privilege},
      credentials: MapSet.new()
    }
  end

  def foothold_nodes(state), do: MapSet.to_list(state.footholds)

  def add_foothold(state, host_id) do
    add_foothold(state, host_id, :user)
  end

  def add_foothold(state, host_id, privilege) do
    current_privilege = Map.get(state.privileges, host_id, :none)

    if privilege_order(privilege) > privilege_order(current_privilege) do
      %{
        state
        | footholds: MapSet.put(state.footholds, host_id),
          privileges: Map.put(state.privileges, host_id, privilege)
      }
    else
      %{state | footholds: MapSet.put(state.footholds, host_id)}
    end
  end

  def privilege_for(state, host_id) do
    Map.get(state.privileges, host_id, :none)
  end

  def has_privilege?(state, host_id, required) do
    current = privilege_for(state, host_id)
    privilege_order(current) >= privilege_order(required)
  end

  def add_credential(state, credential_id) do
    %{state | credentials: MapSet.put(state.credentials, credential_id)}
  end

  def has_credential?(state, credential_id) do
    MapSet.member?(state.credentials, credential_id)
  end

  def attempted?(state, action_key), do: MapSet.member?(state.attempted_actions, action_key)

  def mark_attempted(state, action_key) do
    %{state | attempted_actions: MapSet.put(state.attempted_actions, action_key)}
  end

  defp privilege_order(privilege) when is_atom(privilege),
    do: Map.get(@privilege_order, privilege, 0)

  defp privilege_order("none"), do: 0
  defp privilege_order("user"), do: 1
  defp privilege_order("administrator"), do: 2
  defp privilege_order(_), do: 0
end
