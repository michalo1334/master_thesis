defmodule NetworkDefense.Simulation.Contracts.SimulationParamsTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Rules.Registry, as: RulesRegistry
  alias NetworkDefense.Simulation.Contracts.SimulationParams

  test "accepts explicit rules and a feasibility policy" do
    assert SimulationParams.changeset(%SimulationParams{}, params()).valid?
  end

  test "RTYPE-01: a valid request materializes the rule identifiers as atoms" do
    assert {:ok, %SimulationParams{rules: rules}} = SimulationParams.validate(params())

    assert rules == RulesRegistry.values()
  end

  test "rejects a missing rule subset" do
    changeset = SimulationParams.changeset(%SimulationParams{}, Map.delete(params(), "rules"))

    refute changeset.valid?
    assert {"can't be blank", _options} = Keyword.fetch!(changeset.errors, :rules)
  end

  test "rejects a missing feasibility policy" do
    changeset =
      SimulationParams.changeset(
        %SimulationParams{},
        Map.delete(params(), "require_pre_attack_feasibility")
      )

    refute changeset.valid?

    assert {"can't be blank", _options} =
             Keyword.fetch!(changeset.errors, :require_pre_attack_feasibility)
  end

  test "RTYPE-02: a rule identifier outside the registry is rejected without creating an atom" do
    changeset =
      SimulationParams.changeset(%SimulationParams{}, %{
        params()
        | "rules" => ["zetetic_rule"]
      })

    refute changeset.valid?
    assert {"is invalid", _options} = Keyword.fetch!(changeset.errors, :rules)
    assert_raise ArgumentError, fn -> String.to_existing_atom("zetetic_rule") end
  end

  test "rejects a negative seed" do
    changeset = SimulationParams.changeset(%SimulationParams{}, %{params() | "seed" => -1})

    refute changeset.valid?
    assert {"must be greater than or equal to %{number}", options} = changeset.errors[:seed]
    assert options[:number] == 0
  end

  defp params do
    %{
      "monte_carlo_trials" => 1,
      "iterations_per_run" => 1,
      "initial_foothold_node_id" => Ecto.UUID.generate(),
      "generate_seed" => false,
      "seed" => 1,
      "max_attempts" => 1,
      "rules" => Enum.map(RulesRegistry.values(), &Atom.to_string/1),
      "require_pre_attack_feasibility" => true
    }
  end
end
