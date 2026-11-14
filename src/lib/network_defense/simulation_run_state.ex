defmodule NetworkDefense.SimulationRunState do
  @moduledoc false

  @type t :: map()

  @spec current_iteration(t()) :: map() | nil
  def current_iteration(state) when is_map(state) do
    case Map.fetch!(state, :iterations) do
      [] -> nil
      iterations -> Enum.max_by(iterations, & &1.index)
    end
  end

  @spec current_attacker_state(t()) :: map()
  def current_attacker_state(state) when is_map(state) do
    case current_iteration(state) do
      nil -> Map.fetch!(state, :initial_attacker_state)
      iteration -> Map.fetch!(iteration, :attacker_state)
    end
  end
end
