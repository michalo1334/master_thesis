defmodule NetworkDefense.Evaluation.Study.DefinitionContractsTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.DefenseActions.Registry, as: DefenseActionRegistry
  alias NetworkDefense.Evaluation.Study.Contracts.{Definition, StudyError}
  alias NetworkDefense.Evaluation.Study.Yaml
  alias NetworkDefense.Evaluation.StudyConformance
  alias NetworkDefense.Registry
  alias NetworkDefense.Simulation.Simulator

  # The study definition is the one place that holds every executable setting.
  # The retained cases prove three properties:
  #
  # 1. the checked-in example parses into typed blocks and encodes back to the
  #    same JSON, from YAML as well as from JSON;
  # 2. the scientific cross-field rules and the declared shape are strict, so a
  #    raw value is never coerced and an unknown field never survives;
  # 3. every rejection is one bounded envelope that repeats no document value
  #    and encodes as JSON.
  #
  # Seeds follow one model. A phase declares ordered plan-row selection seeds
  # and one evaluation root per tier. A plan row consumes its selection seed as
  # the optimizer seed input; attack columns derive from the phase root through
  # the existing child-seed policy. No seed value is unique across the whole
  # document, because no contract requires that.

  @max_issue_message_bytes 256
  @max_issues 50
  @max_entries 10_000

  # Every float-backed setting of the definition. Ecto converts each one with
  # :erlang.float/1, so an integer beyond float range must fail at its own path
  # instead of raising.
  @float_setting_paths [
    ["family", "alpha"],
    ["pilot", "analysis", "target_half_width"],
    ["pilot", "analysis", "guard_quantile"],
    ["pilot", "analysis", "confidence_level"],
    ["final", "analysis", "alpha"],
    ["final", "analysis", "confidence_level"]
  ]

  describe "STUDY-DEF-01 complete definition" do
    test "the checked-in definition parses into typed blocks" do
      assert {:ok, %Definition{}} = Definition.parse(StudyConformance.definition())
    end

    test "the checked-in document normalizes from JSON and YAML" do
      definition = StudyConformance.parsed!()

      assert Definition.to_params(definition) == StudyConformance.definition()

      assert {:ok, from_yaml} = Yaml.parse(StudyConformance.yaml())
      assert from_yaml == StudyConformance.definition()
      assert {:ok, yaml_definition} = Definition.parse(from_yaml)
      assert Definition.to_params(yaml_definition) == StudyConformance.definition()
    end

    test "declared order is preserved and never sorted" do
      attrs =
        StudyConformance.definition()
        |> StudyConformance.update_definition(["family", "comparisons"], &Enum.reverse/1)
        |> StudyConformance.update_definition(["pilot", "candidates"], &Enum.reverse/1)
        |> StudyConformance.update_definition(["graphs"], &Enum.reverse/1)

      assert {:ok, definition} = Definition.parse(attrs)
      assert Enum.map(definition.family.comparisons, & &1.tier) == ["edge", "core"]
      assert Enum.map(definition.pilot.candidates, & &1.id) == ["medium", "small"]
      assert Enum.map(definition.graphs, & &1.tier) == ["edge", "core"]
      assert Definition.to_params(definition) == attrs
    end
  end

  describe "STUDY-DEF-01 strict shape" do
    test "an unknown field at any level is rejected at that field" do
      for path <- [
            ["unknown"],
            ["pilot", "collection", "roots", 0, "unknown"]
          ] do
        error =
          path
          |> then(&StudyConformance.put_in_definition(&1, %{"value" => 1}))
          |> StudyConformance.parse_error()

        assert %StudyError{code: "validation_failed"} = error
        assert_schema_error_at(error, path)
      end
    end

    test "a missing setting is rejected at its container path" do
      for {path, container} <- [
            {["graphs", 0, "strategies", 1, "scoring"], ["graphs", 0, "strategies", 1]},
            {["pilot", "collection", "roots"], ["pilot", "collection"]}
          ] do
        error = path |> StudyConformance.delete_key_definition() |> StudyConformance.parse_error()

        assert %StudyError{code: "validation_failed"} = error
        assert_schema_error_at(error, container)
      end
    end

    test "a raw type is rejected instead of coerced" do
      for {path, value} <- [
            {["pilot", "collection", "plan_count_per_side"], "6"},
            {["graphs", 0, "strategies", 1, "require_pre_attack_feasibility"], "true"}
          ] do
        error =
          path
          |> then(&StudyConformance.put_in_definition(&1, value))
          |> StudyConformance.parse_error()

        assert %StudyError{code: "validation_failed"} = error
        assert_schema_error_at(error, path)
      end
    end

    test "a count below its bound is rejected at its path" do
      for {path, value} <- [
            {["pilot", "candidates", 0, "plan_count_per_side"], 0},
            {["pilot", "candidates", 0, "attacks_per_plan"], 0}
          ] do
        error =
          path
          |> then(&StudyConformance.put_in_definition(&1, value))
          |> StudyConformance.parse_error()

        assert %StudyError{code: "validation_failed"} = error
        assert_schema_error_at(error, path)
      end
    end

    test "an unsupported enum value is rejected at its path" do
      for {path, value} <- [
            {["graphs", 0, "strategies", 0, "key"], "heuristic"},
            {["simulation", "rules", 0], "NetworkDefense.Rules.UnknownRule"}
          ] do
        error =
          path
          |> then(&StudyConformance.put_in_definition(&1, value))
          |> StudyConformance.parse_error()

        assert %StudyError{code: "validation_failed"} = error
        assert_schema_error_at(error, path)
      end
    end

    test "a deterministic strategy cannot declare a scoring block" do
      path = ["graphs", 0, "strategies", 0, "scoring"]

      error =
        path
        |> then(
          &StudyConformance.put_in_definition(&1, %{
            "objective" => "mission_impact_only",
            "monte_carlo_trials" => 4,
            "iterations_per_run" => 4,
            "max_attempts" => 4,
            "rules" => supported_rules()
          })
        )
        |> StudyConformance.parse_error()

      assert %StudyError{code: "validation_failed"} = error
      assert_schema_error_at(error, path)
    end

    test "a simulation strategy cannot declare half a scoring block" do
      attrs =
        StudyConformance.delete_key_definition([
          "graphs",
          0,
          "strategies",
          1,
          "scoring",
          "rules"
        ])

      assert_schema_error_at(
        StudyConformance.parse_error(attrs),
        ["graphs", 0, "strategies", 1, "scoring"]
      )

      missing_object =
        StudyConformance.delete_key_definition(["graphs", 0, "strategies", 1, "scoring"])

      assert_schema_error_at(
        StudyConformance.parse_error(missing_object),
        ["graphs", 0, "strategies", 1]
      )
    end

    test "a value that is not valid JSON is rejected before the schema" do
      error = StudyConformance.parse_error(%{"schema_version" => :one})

      assert %StudyError{code: "validation_failed"} = error
      assert issue_at(error, "invalid_json_value", ["schema_version"])

      assert %StudyError{code: "validation_failed"} = StudyConformance.parse_error(%{})
      assert %StudyError{code: "validation_failed"} = StudyConformance.parse_error("study")
    end
  end

  describe "STUDY-DEF-01 JSON boundary errors" do
    test "an invalid UTF-8 map key is rejected at its containing map" do
      error = StudyConformance.parse_error(%{<<255>> => %{"x" => :bad}})

      assert issue_at(error, "invalid_json_value", [])
      assert_encodable(error)
      refute inspect(error) =~ "bad"
    end

    test "an invalid UTF-8 scalar is rejected at its exact path" do
      attrs =
        StudyConformance.put_in_definition(["study", "id"], <<255, 254>>)

      error = StudyConformance.parse_error(attrs)

      assert issue_at(error, "invalid_json_value", ["study", "id"])
      assert_encodable(error)
    end

    test "deep nesting is rejected with an encodable bounded path" do
      nested =
        Enum.reduce(1..40, "leaf", fn _depth, value -> %{"nested" => value} end)

      error = StudyConformance.parse_error(nested)

      assert %StudyError{code: "validation_failed"} = error
      assert_encodable(error)

      assert Enum.all?(Enum.at(error.issues, 0)["path"], fn segment ->
               is_binary(segment) or is_integer(segment)
             end)
    end
  end

  describe "STUDY-DEF-01 technical bounds" do
    test "a number beyond float range never raises at a float field" do
      beyond = Integer.pow(10, 400)
      digits = Integer.to_string(beyond)

      for path <- @float_setting_paths do
        attrs = StudyConformance.put_in_definition(path, beyond)
        error = StudyConformance.parse_error(attrs)

        assert %StudyError{code: "validation_failed"} = error
        issue = issue_at(error, "unrepresentable_number", path)
        assert issue["details"] == %{}
        assert_encodable(error)
        refute error_text(error) =~ digits
      end
    end

    test "a large but representable number is accepted" do
      attrs =
        StudyConformance.put_in_definition(
          ["pilot", "analysis", "target_half_width"],
          Integer.pow(10, 300)
        )

      assert {:ok, definition} = Definition.parse(attrs)
      assert definition.pilot.analysis.target_half_width == 1.0e300
    end

    test "several collections may each fill the entry limit" do
      pilot = Enum.to_list(1..5_000)
      final = Enum.to_list(10_001..15_000)

      yaml =
        "pilot_seeds: [#{Enum.join(pilot, ", ")}]\nfinal_seeds: [#{Enum.join(final, ", ")}]\n"

      assert {:ok, %{"pilot_seeds" => parsed_pilot}} = Yaml.parse(yaml)
      assert Enum.count(parsed_pilot) == 5_000

      attrs =
        StudyConformance.definition()
        |> StudyConformance.put_in_definition(["pilot", "collection", "selection_seeds"], pilot)
        |> StudyConformance.put_in_definition(["final", "collection", "selection_seeds"], final)

      assert {:ok, definition} = Definition.parse(attrs)
      assert Enum.count(definition.pilot.collection.selection_seeds) == 5_000
      assert Enum.count(definition.final.collection.selection_seeds) == 5_000
    end

    test "one collection at the entry limit is accepted and one above it is rejected" do
      accepted =
        StudyConformance.put_in_definition(
          ["pilot", "collection", "selection_seeds"],
          Enum.to_list(1..@max_entries)
        )

      assert {:ok, definition} = Definition.parse(accepted)
      assert Enum.count(definition.pilot.collection.selection_seeds) == @max_entries

      rejected =
        StudyConformance.put_in_definition(
          ["pilot", "collection", "selection_seeds"],
          Enum.to_list(1..(@max_entries + 1))
        )

      error = StudyConformance.parse_error(rejected)

      assert %StudyError{code: "validation_failed"} = error

      issue = issue_at(error, "invalid_json_value", ["pilot", "collection", "selection_seeds"])
      assert issue["details"] == %{"limit" => @max_entries, "actual" => @max_entries + 1}
      assert_encodable(error)

      wide_map = Map.new(1..(@max_entries + 1), &{Integer.to_string(&1), 1})
      map_error = StudyConformance.parse_error(wide_map)
      assert issue_at(map_error, "invalid_json_value", [])
    end
  end

  describe "STUDY-DEF-01 scientific consistency" do
    test "two graphs with one tier are rejected at the second tier" do
      error =
        ["graphs", 1, "tier"]
        |> then(&StudyConformance.put_in_definition(&1, "core"))
        |> StudyConformance.parse_error()

      assert issue_at(error, "duplicate_tier", ["graphs", 1, "tier"])
    end

    test "two strategies with one key in one tier are rejected at the second key" do
      attrs =
        StudyConformance.update_definition(["graphs", 0, "strategies"], fn [first, second] ->
          [first, second, first]
        end)

      error = StudyConformance.parse_error(attrs)

      assert issue_at(error, "duplicate_strategy", ["graphs", 0, "strategies", 2, "key"])
    end

    test "two comparisons with one identity are rejected at the second comparison" do
      attrs =
        StudyConformance.update_definition(["family", "comparisons"], fn comparisons ->
          comparisons ++ [hd(comparisons)]
        end)

      error = StudyConformance.parse_error(attrs)

      assert issue_at(error, "duplicate_comparison", ["family", "comparisons", 2])
    end

    test "two candidates with one identifier or count pair are rejected" do
      repeated_id =
        StudyConformance.update_definition(["pilot", "candidates"], fn candidates ->
          candidates ++ [hd(candidates)]
        end)

      assert issue_at(
               StudyConformance.parse_error(repeated_id),
               "duplicate_candidate_id",
               ["pilot", "candidates", 2]
             )

      repeated_counts =
        StudyConformance.definition()
        |> StudyConformance.put_in_definition(
          ["pilot", "candidates", 1, "plan_count_per_side"],
          5
        )
        |> StudyConformance.put_in_definition(["pilot", "candidates", 1, "attacks_per_plan"], 10)

      assert issue_at(
               StudyConformance.parse_error(repeated_counts),
               "duplicate_candidate_counts",
               ["pilot", "candidates", 1]
             )
    end

    test "a comparison tier must name a declared graph" do
      error =
        ["family", "comparisons", 0, "tier"]
        |> then(&StudyConformance.put_in_definition(&1, "spine"))
        |> StudyConformance.parse_error()

      assert issue_at(error, "unknown_reference", ["family", "comparisons", 0, "tier"])
      assert issue_at(error, "uncovered_tier", ["graphs", 0, "tier"])
    end

    test "a comparison alternative must name a strategy declared for its tier" do
      error =
        ["family", "comparisons", 0, "alternative"]
        |> then(&StudyConformance.put_in_definition(&1, "random"))
        |> StudyConformance.parse_error()

      assert issue_at(error, "unknown_reference", ["family", "comparisons", 0, "alternative"])
    end

    test "a comparison reference must be the cvss strategy" do
      error =
        ["family", "comparisons", 0, "reference"]
        |> then(&StudyConformance.put_in_definition(&1, "simulation_informed"))
        |> StudyConformance.parse_error()

      assert issue_at(error, "unsupported_reference", ["family", "comparisons", 0, "reference"])
    end

    test "a comparison budget must equal the declared strategy budget" do
      error =
        ["family", "comparisons", 0, "budget"]
        |> then(&StudyConformance.put_in_definition(&1, 6))
        |> StudyConformance.parse_error()

      assert issue_at(error, "budget_mismatch", ["family", "comparisons", 0, "budget"])
    end

    test "the final alpha must equal the family alpha" do
      error =
        ["final", "analysis", "alpha"]
        |> then(&StudyConformance.put_in_definition(&1, 0.1))
        |> StudyConformance.parse_error()

      assert issue_at(error, "alpha_mismatch", ["final", "analysis", "alpha"])
    end
  end

  describe "STUDY-DEF-01 evaluation roots" do
    test "a missing tier root is rejected at the roots list" do
      attrs = StudyConformance.delete_entry_definition(["pilot", "collection", "roots", 1])

      assert issue_at(StudyConformance.parse_error(attrs), "missing_root_role", [
               "pilot",
               "collection",
               "roots"
             ])
    end

    test "an unknown tier root is rejected at its tier" do
      error =
        ["final", "collection", "roots", 1, "tier"]
        |> then(&StudyConformance.put_in_definition(&1, "spine"))
        |> StudyConformance.parse_error()

      assert issue_at(error, "unknown_reference", ["final", "collection", "roots", 1, "tier"])
      assert issue_at(error, "missing_root_role", ["final", "collection", "roots"])
    end

    test "a duplicate tier root is rejected at the second tier" do
      error =
        ["final", "collection", "roots", 1, "tier"]
        |> then(&StudyConformance.put_in_definition(&1, "core"))
        |> StudyConformance.parse_error()

      assert issue_at(error, "duplicate_root_role", ["final", "collection", "roots", 1, "tier"])
    end

    test "one root value cannot serve two phases" do
      pilot_root = StudyConformance.fetch_definition(["pilot", "collection", "roots", 0, "value"])

      error =
        ["final", "collection", "roots", 0, "value"]
        |> then(&StudyConformance.put_in_definition(&1, pilot_root))
        |> StudyConformance.parse_error()

      assert issue_at(error, "overlapping_root", ["final", "collection", "roots", 0, "value"])
    end

    test "two tiers in one phase may share one root value" do
      attrs =
        StudyConformance.definition()
        |> StudyConformance.put_in_definition(
          ["final", "collection", "roots", 1, "value"],
          StudyConformance.fetch_definition(["final", "collection", "roots", 0, "value"])
        )
        |> StudyConformance.put_in_definition(["final", "collection", "selection_seeds", 0], 1)
        |> StudyConformance.put_in_definition(["final", "collection", "selection_seeds", 1], 2)

      assert {:ok, _definition} = Definition.parse(attrs)
    end
  end

  describe "STUDY-DEF-01 selection pools and capacity" do
    test "a selection seed appears once in its own pool" do
      seed =
        StudyConformance.fetch_definition(["pilot", "collection", "selection_seeds", 0])

      error =
        ["pilot", "collection", "selection_seeds", 1]
        |> then(&StudyConformance.put_in_definition(&1, seed))
        |> StudyConformance.parse_error()

      assert issue_at(error, "duplicate_selection_seed", [
               "pilot",
               "collection",
               "selection_seeds",
               1
             ])
    end

    test "pilot and final selection pools are disjoint" do
      seed =
        StudyConformance.fetch_definition(["pilot", "collection", "selection_seeds", 0])

      error =
        ["final", "collection", "selection_seeds", 6]
        |> then(&StudyConformance.put_in_definition(&1, seed))
        |> StudyConformance.parse_error()

      assert issue_at(error, "overlapping_selection_seed", [
               "final",
               "collection",
               "selection_seeds",
               6
             ])
    end

    test "the pilot pool supports one seed per declared plan row" do
      attrs =
        StudyConformance.update_definition(["pilot", "collection", "selection_seeds"], fn seeds ->
          Enum.take(seeds, 5)
        end)

      assert issue_at(
               StudyConformance.parse_error(attrs),
               "insufficient_selection_seeds",
               ["pilot", "collection", "selection_seeds"]
             )
    end

    test "the final pool supports the largest declared candidate" do
      attrs =
        StudyConformance.update_definition(["final", "collection", "selection_seeds"], fn seeds ->
          Enum.take(seeds, 5)
        end)

      assert issue_at(
               StudyConformance.parse_error(attrs),
               "insufficient_selection_seeds",
               ["final", "collection", "selection_seeds"]
             )
    end

    test "pilot collection cannot hold fewer plans than the largest candidate" do
      attrs =
        StudyConformance.update_definition(["pilot", "candidates"], fn candidates ->
          candidates ++ [%{"id" => "large", "plan_count_per_side" => 7, "attacks_per_plan" => 12}]
        end)

      assert issue_at(
               StudyConformance.parse_error(attrs),
               "insufficient_pilot_plans",
               ["pilot", "collection", "plan_count_per_side"]
             )
    end

    test "pilot collection cannot hold fewer attacks than the largest candidate" do
      attrs =
        StudyConformance.update_definition(["pilot", "candidates"], fn candidates ->
          candidates ++ [%{"id" => "large", "plan_count_per_side" => 6, "attacks_per_plan" => 13}]
        end)

      assert issue_at(
               StudyConformance.parse_error(attrs),
               "insufficient_pilot_attacks",
               ["pilot", "collection", "attacks_per_plan"]
             )
    end

    test "unused seeds are allowed and capacity is per side" do
      attrs =
        StudyConformance.update_definition(["final", "collection", "selection_seeds"], fn seeds ->
          seeds ++ [710_008, 710_009, 710_010]
        end)

      assert {:ok, definition} = Definition.parse(attrs)
      assert Enum.count(definition.final.collection.selection_seeds) == 10
    end

    test "a non-scoring family needs no scoring or root duplication" do
      attrs =
        StudyConformance.definition()
        |> replace_strategies([
          non_scoring_strategy("cvss", 4),
          non_scoring_strategy("random", 4)
        ])
        |> StudyConformance.put_in_definition(
          ["family", "comparisons", 0, "alternative"],
          "random"
        )
        |> replace_edge_strategies([
          non_scoring_strategy("cvss", 6),
          non_scoring_strategy("topology_segmentation", 6)
        ])
        |> StudyConformance.put_in_definition(
          ["family", "comparisons", 1, "alternative"],
          "topology_segmentation"
        )

      assert {:ok, definition} = Definition.parse(attrs)

      assert Enum.map(hd(definition.graphs).strategies, & &1.key) == ["cvss", "random"]

      assert Enum.map(definition.graphs |> Enum.at(1) |> Map.fetch!(:strategies), & &1.key) ==
               ["cvss", "topology_segmentation"]
    end

    test "equal final comparison seeds are not rejected" do
      attrs =
        StudyConformance.put_in_definition(["final", "analysis", "comparison_seeds"], [7, 7])

      assert {:ok, definition} = Definition.parse(attrs)
      assert definition.final.analysis.comparison_seeds == [7, 7]
    end

    test "a final comparison seed count must equal the comparison count" do
      for seeds <- [[210_001], [210_001, 210_002, 210_003]] do
        attrs =
          StudyConformance.put_in_definition(["final", "analysis", "comparison_seeds"], seeds)

        assert issue_at(
                 StudyConformance.parse_error(attrs),
                 "comparison_seed_count",
                 ["final", "analysis", "comparison_seeds"]
               )
      end
    end

    test "final counts are declared nowhere, because resume supplies them" do
      attrs =
        StudyConformance.put_in_definition(["final", "collection", "plan_count_per_side"], 6)

      assert_schema_error_at(
        StudyConformance.parse_error(attrs),
        ["final", "collection", "plan_count_per_side"]
      )
    end
  end

  describe "STUDY-DEF-01 bounded errors" do
    test "every rejection is one bounded envelope with no document value" do
      rejections = [
        StudyConformance.put_in_definition(["graphs", 0, "graph_revision_id"], "not-a-uuid"),
        StudyConformance.put_in_definition(
          ["graphs", 0, "strategies", 0, "candidate_action_types", 0],
          "DeleteNode"
        ),
        StudyConformance.put_in_definition(["graphs", 0, "strategies", 0, "key"], "heuristic"),
        StudyConformance.put_in_definition(["study", "revisions", "model"], 7),
        StudyConformance.put_in_definition(["family", "alpha"], "0.05"),
        StudyConformance.put_in_definition(["family", "comparisons", 0, "budget"], 6),
        StudyConformance.delete_key_definition(["simulation", "max_attempts"]),
        StudyConformance.delete_entry_definition(["final", "collection", "roots", 1]),
        StudyConformance.delete_entry_definition(["pilot", "collection", "selection_seeds", 0])
      ]

      for attrs <- rejections do
        error = StudyConformance.parse_error(attrs)

        assert %StudyError{schema_version: 1, code: code} = error
        assert is_binary(code)

        entries = error.issues ++ error.schema_errors
        assert entries != []
        assert length(entries) <= @max_issues

        for entry <- entries do
          assert is_binary(entry["message"])
          assert byte_size(entry["message"]) <= @max_issue_message_bytes
        end

        for issue <- error.issues do
          assert is_binary(issue["code"])
          assert is_list(issue["path"])
          assert Enum.all?(issue["path"], &(is_binary(&1) or is_integer(&1)))
          assert is_map(issue["details"])
        end

        for diagnostic <- error.schema_errors do
          assert is_binary(diagnostic["path"])
          assert is_list(diagnostic["causes"])
        end

        assert_encodable(error)

        refute inspect(error) =~ "not-a-uuid"
        refute inspect(error) =~ "DeleteNode"
        refute inspect(error) =~ "heuristic"
      end
    end
  end

  defp non_scoring_strategy(key, budget) do
    %{
      "key" => key,
      "budget" => budget,
      "candidate_action_types" => candidate_action_types(),
      "require_pre_attack_feasibility" => true
    }
  end

  defp replace_strategies(attrs, strategies) do
    StudyConformance.put_in_definition(
      attrs,
      ["graphs", 0, "strategies"],
      strategies
    )
  end

  defp replace_edge_strategies(attrs, strategies) do
    StudyConformance.put_in_definition(attrs, ["graphs", 1, "strategies"], strategies)
  end

  defp candidate_action_types do
    DefenseActionRegistry.get_all()
    |> MapSet.to_list()
    |> then(&Registry.contract_types/1)
    |> Enum.sort()
  end

  defp supported_rules do
    Simulator.default_rules()
    |> Enum.map(&(&1.__struct__ |> Module.split() |> Enum.join(".")))
    |> Enum.sort()
  end

  defp error_text(%StudyError{} = error) do
    error |> StudyError.to_params() |> Jason.encode!()
  end

  defp assert_schema_error_at(%StudyError{} = error, path) do
    expected = json_path(path)

    assert expected in schema_paths(error),
           "expected a schema error at #{expected}, got: #{inspect(schema_paths(error))}"
  end

  defp assert_encodable(%StudyError{} = error) do
    assert {:ok, encoded} = error |> StudyError.to_params() |> Jason.encode()
    assert is_binary(encoded)
  end

  defp schema_paths(%StudyError{schema_errors: diagnostics}),
    do: diagnostics |> Enum.flat_map(&paths_of/1) |> Enum.uniq()

  defp paths_of(diagnostic) do
    [diagnostic["path"] | Enum.flat_map(diagnostic["causes"] || [], &paths_of/1)]
  end

  defp json_path([]), do: "#"
  defp json_path(segments), do: "#/" <> Enum.join(segments, "/")

  defp issue_at(%StudyError{issues: issues}, code, path) do
    Enum.find(issues, fn issue -> issue["code"] == code and issue["path"] == path end) ||
      flunk("expected issue #{code} at #{inspect(path)}, got: #{inspect(issues)}")
  end
end
