defmodule NetworkDefense.Simulation.Contracts.SimulationParamsTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Simulation.Contracts.SimulationParams

  test "rejects a negative seed" do
    changeset =
      SimulationParams.changeset(%SimulationParams{}, %{
        "monte_carlo_trials" => 1,
        "iterations_per_run" => 1,
        "initial_foothold_node_id" => Ecto.UUID.generate(),
        "generate_seed" => false,
        "seed" => -1,
        "max_attempts" => 1
      })

    refute changeset.valid?
    assert {"must be greater than or equal to %{number}", options} = changeset.errors[:seed]
    assert options[:number] == 0
  end
end
