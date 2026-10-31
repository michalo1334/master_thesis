defmodule NetworkDefense.Evaluation2.DefinitionParseTest do
  @moduledoc """
  Accepted new-format definitions and the construction responsibilities of the
  foundation boundary.

  Cases: INPUT-01 (known fields retained, extras dropped), MODEL-01 (derived
  membership and capacity are not independently declared), POLICY-01 (one shared
  policy, scoring only on scored variants).
  """

  use ExUnit.Case, async: true
  @moduletag :unit

  import NetworkDefense.Evaluation2Test.FoundationFixtures

  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Study.Error

  describe "INPUT-01 accepted document" do
    test "normalizes the declared study identity and shared settings" do
      assert {:ok, definition} = Definition.parse(valid_attrs())

      assert %{study: %{id: "example-study", revision: 1}} = definition
      assert %{seed: 31_415} = definition
      assert %{family: %{id: "primary-family", alpha: 0.05}} = definition
      assert %{analysis: %{confidence_level: 0.95}} = definition

      assert %{
               defense: %{
                 allowed_action_types: [
                   :patch_vulnerability,
                   :block_segment_reachability,
                   :revoke_credential
                 ]
               }
             } = definition

      assert %{
               simulation: %{
                 iterations_per_run: 12,
                 max_attempts: 3,
                 rules: [:remote_service_exploitation, :reuse_credential_rule]
               }
             } = definition

      assert %{pilot: %{candidates: candidates, extra_pool: %{plans: 10, attacks: 20}}} =
               definition

      assert Enum.map(candidates, &{&1.id, &1.plans, &1.attacks}) == [
               {"smaller", 10, 20},
               {"larger", 20, 40}
             ]

      assert %{pilot: %{precision: %{outer_subsamples: 50}}} = definition
    end

    test "keeps the declared tier inputs in tier order" do
      assert {:ok, definition} = Definition.parse(valid_attrs())

      assert Enum.map(definition.tiers, &tier_name/1) == ["small", "medium", "large"]

      assert graph_revision_ids(definition) ==
               Map.new(tier_graph_ids(), fn {k, v} -> {to_string(k), v} end)

      assert foothold_node_ids(definition) ==
               Map.new(tier_foothold_ids(), fn {k, v} -> {to_string(k), v} end)
    end

    test "records frozen provenance that the operator did not declare" do
      assert {:ok, definition} = Definition.parse(valid_attrs())

      refute Map.get(valid_attrs(), "provenance")
      assert %{provenance: provenance} = definition
      assert %{method: method, seed_contract: seed_contract} = provenance
      assert is_binary(method) and method != ""
      assert is_binary(seed_contract) and seed_contract != ""
    end

    test "drops unknown keys at every declared position" do
      attrs =
        attrs_with([
          {["schema_version"], 7},
          {["revisions"], %{"application" => "asserted-by-operator"}},
          {["final"], %{}},
          {["study", "owner"], "operator"},
          {["family", "bootstrap_replicates"], 200},
          {["analysis", "bootstrap_replicates"], 200},
          {["defense", "per_strategy_permissions"], %{}},
          {["simulation", "iterations_per_budget"], 3},
          {["tiers", "small", "notes"], "ignored"},
          {["pilot", "precision", "confidence_level"], 0.99}
        ])
        |> update_in(["tiers", "small", "alternatives"], fn [first | rest] ->
          [Map.put(first, "action_types", ["revoke_credential"]) | rest]
        end)

      assert {:ok, definition} = Definition.parse(attrs)

      assert %{family: %{alpha: 0.05}} = definition
      assert %{analysis: %{confidence_level: 0.95}} = definition

      dropped = [
        :extra_root,
        :revisions,
        :schema_version,
        :bootstrap_replicates,
        :owner,
        :per_strategy_permissions,
        :iterations_per_budget,
        :notes,
        :action_types
      ]

      for key <- dropped do
        assert key_count(definition, key) == 0,
               "expected the extra key #{inspect(key)} to be dropped"
      end

      refute Map.has_key?(definition, :final), "an empty Final block must not survive"
    end

    test "projects only the three supported tier slots" do
      attrs =
        valid_attrs()
        |> Map.put("tiers", Map.put(valid_attrs()["tiers"], "extra_large", %{"budgets" => [4]}))

      assert {:ok, definition} = Definition.parse(attrs)
      assert Enum.map(definition.tiers, &tier_name/1) == ["small", "medium", "large"]
    end

    test "defaults the shared feasibility policy to required" do
      attrs = attrs_with([{:delete, ["defense", "feasibility"]}])

      assert {:ok, definition} = Definition.parse(attrs)
      assert %{defense: %{feasibility: :required}} = definition
    end

    test "accepts the explicit unrestricted feasibility policy" do
      attrs = attrs_with([{["defense", "feasibility"], "unrestricted"}])

      assert {:ok, definition} = Definition.parse(attrs)
      assert %{defense: %{feasibility: :unrestricted}} = definition
    end

    test "accepts an empty extra pool and a zero lower seed" do
      attrs =
        attrs_with([
          {["pilot", "extra_pool"], %{"plans" => 0, "attacks" => 0}},
          {["seed"], 0}
        ])

      assert {:ok, definition} = Definition.parse(attrs)
      assert %{seed: 0, pilot: %{extra_pool: %{plans: 0, attacks: 0}}} = definition
    end

    test "reports a bounded error instead of raising for a non-mapping document" do
      assert {:error, %Error{category: :validation_failed, issues: issues}} =
               Definition.parse([])

      assert issues != []
    end
  end

  describe "MODEL-01 derived facts" do
    test "does not store an independent comparison or capacity declaration" do
      attrs =
        attrs_with([
          {["comparisons"], [%{"tier" => "small", "budget" => 999}]},
          {["capacity"], %{"plans" => 999, "attacks" => 999}},
          {["absolute_capacity"], %{"plans" => 999}},
          {["collection_groups"], []}
        ])

      assert {:ok, definition} = Definition.parse(attrs)

      for key <- [:comparisons, :capacity, :absolute_capacity, :collection_groups] do
        assert key_count(definition, key) == 0,
               "derived facts must not be stored as declarations: #{inspect(key)}"
      end

      assert Enum.count(Definition.comparisons(definition)) == 9
      assert %{plans: 30, attacks: 60} = Definition.pilot_capacity(definition)
    end

    test "keeps derived views unchanged when unrelated declaration order changes" do
      reordered =
        attrs_with([
          {["pilot", "candidates"], Enum.reverse(valid_attrs()["pilot"]["candidates"])},
          {["defense", "allowed_action_types"],
           Enum.reverse(valid_attrs()["defense"]["allowed_action_types"])}
        ])

      assert {:ok, default} = Definition.parse(valid_attrs())
      assert {:ok, other} = Definition.parse(reordered)

      assert Definition.comparisons(default) == Definition.comparisons(other)
      assert Definition.pilot_capacity(default) == Definition.pilot_capacity(other)
    end
  end

  describe "POLICY-01 shared policy and strategy requests" do
    test "declares one shared defense policy and one shared simulation model" do
      assert {:ok, definition} = Definition.parse(valid_attrs())

      assert key_count(definition, :allowed_action_types) == 1
      assert key_count(definition, :feasibility) == 1
      assert key_count(definition, :rules) == 1
      assert key_count(definition, :iterations_per_run) == 1
      assert key_count(definition, :confidence_level) == 1
    end

    test "carries scoring only on the scored alternative" do
      assert {:ok, definition} = Definition.parse(valid_attrs())

      declared =
        Map.new(definition.tiers, fn tier ->
          {tier_name(tier), Enum.map(alternatives(tier), &{strategy_name(&1), scoring(&1)})}
        end)

      assert %{"small" => small, "medium" => medium, "large" => large} = declared
      assert Enum.map(small, &elem(&1, 0)) == [:random, :simulation_informed]
      assert Enum.map(medium, &elem(&1, 0)) == [:simulation_informed, :random]
      assert Enum.map(large, &elem(&1, 0)) == [:random]

      assert [nil, scored] = Enum.map(small, &elem(&1, 1))
      assert %{objective: :mission_impact_only, monte_carlo_trials: 50} = scored
      assert [scored | _rest] = Enum.map(medium, &elem(&1, 1))
      assert %{objective: :mission_impact_only, monte_carlo_trials: 50} = scored
      assert [nil] = Enum.map(large, &elem(&1, 1))
    end

    test "an alternative cannot narrow the shared defense policy" do
      narrow = %{
        "allowed_action_types" => ["revoke_credential"],
        "feasibility" => "unrestricted"
      }

      attrs =
        update_in(valid_attrs(), ["tiers", "small", "alternatives"], fn [first | rest] ->
          [Map.merge(first, narrow) | rest]
        end)

      assert {:ok, definition} = Definition.parse(attrs)

      assert key_count(definition, :allowed_action_types) == 1
      assert key_count(definition, :feasibility) == 1

      assert %{
               defense: %{
                 feasibility: :required,
                 allowed_action_types: [
                   :patch_vulnerability,
                   :block_segment_reachability,
                   :revoke_credential
                 ]
               }
             } = definition
    end

    test "every tier alternative stays inside the supported strategy vocabulary" do
      assert {:ok, definition} = Definition.parse(valid_attrs())

      keys =
        definition.tiers
        |> Enum.flat_map(&alternatives/1)
        |> Enum.map(&strategy_name/1)

      assert Enum.all?(keys, &primary_strategy?/1)

      for excluded <- [:cvss, :null] do
        refute excluded in keys,
               "the CVSS reference and the no-defense strategy are not primary alternatives"
      end
    end
  end
end
