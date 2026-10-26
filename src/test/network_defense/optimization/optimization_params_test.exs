defmodule NetworkDefense.Optimization.OptimizationParamsTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Optimization.Contracts.{OptimizationParams, RunOptimizationRequest}
  alias NetworkDefense.Rules.Registry, as: RulesRegistry

  @foothold Ecto.UUID.generate()

  @scoring %{
    "objective" => "mission_then_blast_radius",
    "monte_carlo_trials" => 1,
    "iterations_per_run" => 1,
    "max_attempts" => 1,
    "rules" => Enum.map(RulesRegistry.values(), &Atom.to_string/1)
  }

  for strategy <- ["simulation_informed", "simulated_annealing"] do
    test "accepts complete scoring settings for #{strategy}" do
      changeset = OptimizationParams.changeset(%OptimizationParams{}, params(unquote(strategy)))

      assert changeset.valid?
    end
  end

  test "RTYPE-ALIAS-01: a valid request materializes every closed-set value as an atom" do
    assert {:ok, params} = OptimizationParams.validate(params("simulation_informed"))

    assert params.strategy == :simulation_informed
    assert params.candidate_action_types == [:patch_vulnerability]
    assert params.simulation_params.objective == :mission_then_blast_radius
    assert params.simulation_params.rules == RulesRegistry.values()
  end

  test "RTYPE-ALIAS-02: an unknown closed-set value is rejected without creating an atom" do
    action_changeset =
      OptimizationParams.changeset(%OptimizationParams{}, %{
        params("cvss")
        | "candidate_action_types" => ["zetetic_action"]
      })

    refute action_changeset.valid?

    assert {"is invalid", _options} =
             Keyword.fetch!(action_changeset.errors, :candidate_action_types)

    assert_raise ArgumentError, fn -> String.to_existing_atom("zetetic_action") end

    strategy_changeset =
      OptimizationParams.changeset(%OptimizationParams{}, %{
        params("cvss")
        | "strategy" => "zetetic_strategy"
      })

    refute strategy_changeset.valid?
    assert {"is invalid", _options} = Keyword.fetch!(strategy_changeset.errors, :strategy)
    assert_raise ArgumentError, fn -> String.to_existing_atom("zetetic_strategy") end

    objective_changeset =
      OptimizationParams.changeset(%OptimizationParams{}, %{
        params("simulation_informed")
        | "simulation_params" => %{@scoring | "objective" => "zetetic_objective"}
      })

    refute objective_changeset.valid?

    assert %{simulation_params: %{objective: ["is invalid"]}} =
             Ecto.Changeset.traverse_errors(objective_changeset, fn {message, _options} ->
               message
             end)

    assert_raise ArgumentError, fn -> String.to_existing_atom("zetetic_objective") end
  end

  test "REMBED-01: a scoring strategy without scoring settings reports the embed as required" do
    changeset =
      OptimizationParams.changeset(
        %OptimizationParams{},
        Map.delete(params("simulation_informed"), "simulation_params")
      )

    refute changeset.valid?
    assert {"can't be blank", _options} = Keyword.fetch!(changeset.errors, :simulation_params)
  end

  test "REMBED-02: a non-scoring strategy rejects supplied scoring settings" do
    changeset =
      OptimizationParams.changeset(
        %OptimizationParams{},
        Map.delete(params("cvss"), "initial_foothold_node_id")
      )

    refute changeset.valid?

    assert {"is not supported for this strategy", []} =
             Keyword.fetch!(changeset.errors, :simulation_params)

    refute Map.has_key?(changeset.changes, :simulation_params)
  end

  test "an unknown strategy adds no secondary scoring error" do
    changeset =
      OptimizationParams.changeset(%OptimizationParams{}, %{
        params("simulation_informed")
        | "strategy" => "zetetic_strategy"
      })

    refute changeset.valid?
    assert {"is invalid", _options} = Keyword.fetch!(changeset.errors, :strategy)
    refute Keyword.has_key?(changeset.errors, :simulation_params)
    refute Keyword.has_key?(changeset.errors, :initial_foothold_node_id)
  end

  test "accepts a topology segmentation request without scoring settings" do
    changeset =
      OptimizationParams.changeset(
        %OptimizationParams{},
        Map.delete(params("topology_segmentation"), "simulation_params")
      )

    assert changeset.valid?
    assert Map.has_key?(changeset.changes, :simulation_params) == false
  end

  test "requires an explicit foothold for a strategy that reads one" do
    changeset =
      OptimizationParams.changeset(
        %OptimizationParams{},
        Map.delete(params("topology_segmentation"), "initial_foothold_node_id")
      )

    refute changeset.valid?

    assert {"is required", _options} = Keyword.fetch!(changeset.errors, :initial_foothold_node_id)
  end

  test "requires explicit action and feasibility settings" do
    changeset =
      OptimizationParams.changeset(%OptimizationParams{}, %{
        "strategy" => "cvss",
        "budget" => 1,
        "seed" => 0
      })

    refute changeset.valid?

    assert {"can't be blank", _options} =
             Keyword.fetch!(changeset.errors, :candidate_action_types)

    assert {"can't be blank", _options} =
             Keyword.fetch!(changeset.errors, :require_pre_attack_feasibility)
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

  defp params(strategy) do
    %{
      "strategy" => strategy,
      "budget" => 1,
      "seed" => 0,
      "candidate_action_types" => ["patch_vulnerability"],
      "require_pre_attack_feasibility" => true,
      "initial_foothold_node_id" => @foothold,
      "simulation_params" => @scoring
    }
  end
end
