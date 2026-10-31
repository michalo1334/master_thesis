defmodule NetworkDefense.Evaluation2.DefinitionRejectionsTest do
  @moduledoc """
  Rejected new-format definitions.

  Every case states one deviation from the valid fixture document, so a rejection
  proves the boundary rejects that declaration instead of the whole document.
  Cases: INPUT-01 (invalid required values), MODEL-01 (duplicate identities and
  count pairs), POLICY-01 (unusable permission and scoring declarations).
  """

  use ExUnit.Case, async: true
  @moduletag :unit

  import NetworkDefense.Evaluation2Test.FoundationFixtures

  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Study.Error

  invalid_documents = [
    {"a missing study block", [{:delete, ["study"]}]},
    {"a missing seed", [{:delete, ["seed"]}]},
    {"a missing family block", [{:delete, ["family"]}]},
    {"a missing analysis block", [{:delete, ["analysis"]}]},
    {"a missing defense block", [{:delete, ["defense"]}]},
    {"a missing simulation block", [{:delete, ["simulation"]}]},
    {"a missing tiers block", [{:delete, ["tiers"]}]},
    {"a missing pilot block", [{:delete, ["pilot"]}]},
    {"an empty study identifier", [{["study", "id"], ""}]},
    {"a non-string study identifier", [{["study", "id"], 7}]},
    {"a zero revision number", [{["study", "revision"], 0}]},
    {"a fractional revision number", [{["study", "revision"], 1.5}]},
    {"a negative seed", [{["seed"], -1}]},
    {"a string seed", [{["seed"], "31415"}]},
    {"a seed at the derivation modulus", [{["seed"], 9_223_372_036_854_775_807}]},
    {"an empty family identifier", [{["family", "id"], ""}]},
    {"an alpha above one", [{["family", "alpha"], 1.5}]},
    {"an alpha of zero", [{["family", "alpha"], 0}]},
    {"a string alpha", [{["family", "alpha"], "0.05"}]},
    {"a confidence level of one", [{["analysis", "confidence_level"], 1.0}]},
    {"a confidence level of zero", [{["analysis", "confidence_level"], 0.0}]},
    {"an empty defense action list", [{["defense", "allowed_action_types"], []}]},
    {"a missing defense action list", [{:delete, ["defense", "allowed_action_types"]}]},
    {"an unregistered defense action",
     [{["defense", "allowed_action_types"], ["patch_vulnerability", "disable_host"]}]},
    {"duplicate defense actions",
     [{["defense", "allowed_action_types"], ["patch_vulnerability", "patch_vulnerability"]}]},
    {"an unsupported feasibility policy", [{["defense", "feasibility"], "sometimes"}]},
    {"an empty rule list", [{["simulation", "rules"], []}]},
    {"an unregistered rule", [{["simulation", "rules"], ["example_rule"]}]},
    {"a zero iteration count", [{["simulation", "iterations_per_run"], 0}]},
    {"a zero attempt count", [{["simulation", "max_attempts"], 0}]},
    {"a missing small tier", [{:delete, ["tiers", "small"]}]},
    {"a missing medium tier", [{:delete, ["tiers", "medium"]}]},
    {"an empty budget list", [{["tiers", "small", "budgets"], []}]},
    {"a zero budget", [{["tiers", "small", "budgets"], [0]}]},
    {"a negative budget", [{["tiers", "small", "budgets"], [4, -8]}]},
    {"a fractional budget", [{["tiers", "small", "budgets"], [4.5]}]},
    {"duplicate budgets", [{["tiers", "small", "budgets"], [4, 4]}]},
    {"an empty alternative list", [{["tiers", "small", "alternatives"], []}]},
    {"a missing alternative list", [{:delete, ["tiers", "small", "alternatives"]}]},
    {"a duplicate alternative",
     [
       {["tiers", "small", "alternatives"],
        [%{"strategy" => "random"}, %{"strategy" => "random"}]}
     ]},
    {"the CVSS reference as a primary alternative",
     [{["tiers", "small", "alternatives"], [%{"strategy" => "cvss"}]}]},
    {"the no-defense strategy as a primary alternative",
     [{["tiers", "small", "alternatives"], [%{"strategy" => "null"}]}]},
    {"an unregistered strategy",
     [{["tiers", "small", "alternatives"], [%{"strategy" => "always_best"}]}]},
    {"a scored alternative without scoring data",
     [{["tiers", "small", "alternatives"], [%{"strategy" => "simulation_informed"}]}]},
    {"scoring data on a simple alternative",
     [
       {["tiers", "small", "alternatives"],
        [
          %{
            "strategy" => "random",
            "scoring" => %{"objective" => "mission_impact_only", "monte_carlo_trials" => 50}
          }
        ]}
     ]},
    {"an unsupported scoring objective",
     [
       {["tiers", "small", "alternatives"],
        [
          %{
            "strategy" => "simulation_informed",
            "scoring" => %{"objective" => "total_damage", "monte_carlo_trials" => 50}
          }
        ]}
     ]},
    {"a zero scoring trial count",
     [
       {["tiers", "small", "alternatives"],
        [
          %{
            "strategy" => "simulation_informed",
            "scoring" => %{"objective" => "mission_impact_only", "monte_carlo_trials" => 0}
          }
        ]}
     ]},
    {"a non-UUID graph revision identifier",
     [{["tiers", "small", "graph_revision_id"], "small-graph"}]},
    {"a missing graph revision identifier", [{:delete, ["tiers", "small", "graph_revision_id"]}]},
    {"a missing foothold node identifier", [{:delete, ["tiers", "small", "foothold_node_id"]}]},
    {"a non-UUID foothold node identifier", [{["tiers", "small", "foothold_node_id"], "host"}]},
    {"an empty candidate list", [{["pilot", "candidates"], []}]},
    {"a missing candidate list", [{:delete, ["pilot", "candidates"]}]},
    {"duplicate candidate identifiers",
     [
       {["pilot", "candidates"],
        [
          %{"id" => "same", "plans" => 10, "attacks" => 20},
          %{"id" => "same", "plans" => 20, "attacks" => 40}
        ]}
     ]},
    {"duplicate candidate count pairs",
     [
       {["pilot", "candidates"],
        [
          %{"id" => "one", "plans" => 10, "attacks" => 20},
          %{"id" => "two", "plans" => 10, "attacks" => 20}
        ]}
     ]},
    {"a candidate without a plan count",
     [{["pilot", "candidates"], [%{"id" => "one", "attacks" => 20}]}]},
    {"a zero candidate plan count",
     [{["pilot", "candidates"], [%{"id" => "one", "plans" => 0, "attacks" => 20}]}]},
    {"a zero candidate attack count",
     [{["pilot", "candidates"], [%{"id" => "one", "plans" => 10, "attacks" => 0}]}]},
    {"a missing extra pool", [{:delete, ["pilot", "extra_pool"]}]},
    {"a negative extra plan count", [{["pilot", "extra_pool", "plans"], -1}]},
    {"a missing precision block", [{:delete, ["pilot", "precision"]}]},
    {"a zero outer subsample count", [{["pilot", "precision", "outer_subsamples"], 0}]},
    {"a zero target half width", [{["pilot", "precision", "target_half_width"], 0}]},
    {"a guard quantile of one", [{["pilot", "precision", "guard_quantile"], 1.0}]},
    {"a guard quantile of zero", [{["pilot", "precision", "guard_quantile"], 0.0}]}
  ]

  for {label, overrides} <- invalid_documents do
    test "INPUT-01 rejects #{label}" do
      assert {:error, %Error{category: :validation_failed, issues: issues}} =
               Definition.parse(attrs_with(unquote(Macro.escape(overrides))))

      assert is_list(issues) and issues != [], "a rejection must carry at least one issue"

      for issue <- issues do
        assert %{code: code, path: path, message: message} = issue
        assert is_binary(code) and code != ""
        assert is_list(path)
        assert is_binary(message) and message != ""
      end
    end
  end

  test "INPUT-01 rejects a document root that is not a mapping" do
    assert {:error, %Error{category: :validation_failed}} = Definition.parse("study")
  end

  test "INPUT-01 rejects an empty document" do
    assert {:error, %Error{category: :validation_failed}} = Definition.parse(%{})
  end

  test "POLICY-01 rejects a scored alternative whose scoring block is not a mapping" do
    attrs =
      update_in(valid_attrs(), ["tiers", "small", "alternatives"], fn [first | rest] ->
        [Map.put(first, "scoring", 50) | rest]
      end)

    assert {:error, %Error{category: :validation_failed}} = Definition.parse(attrs)
  end
end
