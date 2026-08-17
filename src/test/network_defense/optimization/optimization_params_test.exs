defmodule NetworkDefense.Optimization.OptimizationParamsTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Optimization.Contracts.OptimizationParams

  for strategy <- ["simulation_informed", "topology_segmentation", "simulated_annealing"] do
    test "accepts simulation parameters for #{strategy}" do
      changeset =
        OptimizationParams.changeset(%OptimizationParams{}, %{
          "strategy" => unquote(strategy),
          "budget" => 1,
          "simulation_params" => %{
            "monte_carlo_trials" => 1,
            "iterations_per_run" => 1,
            "initial_foothold_node_id" => Ecto.UUID.generate(),
            "generate_seed" => true,
            "max_attempts" => 1
          }
        })

      assert changeset.valid?
    end
  end

  for strategy <- ["simulation_informed", "topology_segmentation", "simulated_annealing"] do
    test "requires simulation parameters for #{strategy}" do
      changeset =
        OptimizationParams.changeset(%OptimizationParams{}, %{
          "strategy" => unquote(strategy),
          "budget" => 1
        })

      refute changeset.valid?
      assert {"is required", []} = Keyword.fetch!(changeset.errors, :simulation_params)
    end
  end
end
