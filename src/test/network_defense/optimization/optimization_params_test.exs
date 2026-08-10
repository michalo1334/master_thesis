defmodule NetworkDefense.Optimization.OptimizationParamsTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Optimization.Contracts.OptimizationParams

  for strategy <- ["topology_segmentation", "simulated_annealing"] do
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

  test "requires simulation parameters for topology segmentation" do
    changeset =
      OptimizationParams.changeset(%OptimizationParams{}, %{
        "strategy" => "topology_segmentation",
        "budget" => 1
      })

    refute changeset.valid?
    assert {"is required", []} = Keyword.fetch!(changeset.errors, :simulation_params)
  end

  test "accepts mission impact as a simulation-backed optimization objective" do
    changeset =
      OptimizationParams.changeset(%OptimizationParams{}, %{
        "strategy" => "simulation_informed",
        "objective" => "mission_impact",
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

  test "requires an objective" do
    changeset =
      OptimizationParams.changeset(%OptimizationParams{}, %{
        "strategy" => "cvss",
        "objective" => nil,
        "budget" => 1
      })

    refute changeset.valid?
    assert {"can't be blank", _} = Keyword.fetch!(changeset.errors, :objective)
  end

  for strategy <- ["cvss", "topology_segmentation"] do
    test "rejects mission impact for #{strategy}" do
      changeset =
        OptimizationParams.changeset(%OptimizationParams{}, %{
          "strategy" => unquote(strategy),
          "objective" => "mission_impact",
          "budget" => 1,
          "simulation_params" => %{
            "monte_carlo_trials" => 1,
            "iterations_per_run" => 1,
            "initial_foothold_node_id" => Ecto.UUID.generate(),
            "generate_seed" => true,
            "max_attempts" => 1
          }
        })

      refute changeset.valid?

      assert {"is unsupported by the selected strategy", []} =
               Keyword.fetch!(changeset.errors, :objective)
    end
  end
end
