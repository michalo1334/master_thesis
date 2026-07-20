defmodule NetworkDefense.Simulations do
  @moduledoc """
  Public context module for working with simulation related aspects
  """
  alias NetworkDefense.Simulation.MultiStates
  alias NetworkDefense.Simulation.Simulator
  alias NetworkDefense.Simulation.States

  def run(opts \\ []) do
    state = Simulator.run(opts)
    {:ok, saved} = States.insert(state)
    saved
  end

  def run_multiple(opts \\ []) do
    {multi_state, _states} = Simulator.run_multiple(opts)
    {:ok, saved} = MultiStates.insert(multi_state)
    saved
  end

  def run_async(opts \\ []) do
    Task.start(fn ->
      {:ok, multi_state} = run_multiple(opts)

      Phoenix.PubSub.broadcast(
        NetworkDefense.PubSub,
        "simulation_done",
        {:simulation_done, multi_state.id, "Simulation done!"}
      )
    end)
  end
end
