defmodule NetworkDefense.Optimization.OptimizationParamsTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Optimization.Contracts.{OptimizationParams, RunOptimizationRequest}

  for strategy <- ["simulation_informed", "topology_segmentation", "simulated_annealing"] do
    test "accepts simulation parameters for #{strategy}" do
      changeset =
        OptimizationParams.changeset(%OptimizationParams{}, %{
          "strategy" => unquote(strategy),
          "budget" => 1,
          "seed" => 0,
          "simulation_params" => %{
            "monte_carlo_trials" => 1,
            "iterations_per_run" => 1,
            "initial_foothold_node_id" => Ecto.UUID.generate(),
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
          "budget" => 1,
          "seed" => 0
        })

      refute changeset.valid?
      assert {"is required", []} = Keyword.fetch!(changeset.errors, :simulation_params)
    end
  end

  test "rejects an optimization request without a seed" do
    assert {:error, changeset} =
             RunOptimizationRequest.validate(%{
               "graph_revision_id" => Ecto.UUID.generate(),
               "correlation_id" => "correlation",
               "optimization_params" => %{"strategy" => "cvss", "budget" => 1}
             })

    assert %{optimization_params: %{seed: ["can't be blank"]}} =
             Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
